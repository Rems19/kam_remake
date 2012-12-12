unit KM_PathFindingNew;
{$I KaM_Remake.inc}
interface
uses SysUtils, Math, KromUtils,
  KM_CommonClasses, KM_Defaults, KM_Houses, KM_Terrain, KM_Points, Unit_Heap;


const
  PATH_CACHE_MAX = 12; //How many paths to cache
  PATH_CACHE_INIT_WEIGHT = 5; //New path weight

type
  TANode = class
             X,Y: SmallInt;
             CostTo: Word;
             Estim: Word;
             Parent: TANode;
           end;

  TDestinationPoint = (
    dp_Location, //Walk to location
    dp_Passability, //Walk to desired passability
    dp_House //Approach house from any side (workers and warriors)
    );

  //This is a helper class for TTerrain
  //Here should be pathfinding and all associated stuff
  //I think we should refactor this unit and move some TTerrain methods here
  TPathFinding = class
  private
    ORef: array of array of TANode; //References to OpenList, Sized as map

    MinN: TANode;

    fCache: array [0 .. PATH_CACHE_MAX - 1] of record
      Weight: Word;
      Pass: TPassabilitySet;
      Route: TKMPointList;
    end;
  private
    fPass: TPassabilitySet;
    fTargetWalkConnect: TWalkConnect;
    fTargetNetwork: Byte;
    fDistance: Single;
    fIsInteractionAvoid: Boolean;
    fDestination: TDestinationPoint;
    fTargetHouse: TKMHouse;
    fWeightRoutes: Boolean;
    procedure AddToCache(NodeList: TKMPointList);
    procedure Reset;
    function TryRouteFromCache(NodeList: TKMPointList): Boolean;
    function MakeRoute: Boolean;
    procedure ReturnRoute(NodeList: TKMPointList);
  protected
    fLocA: TKMPoint;
    fLocB: TKMPoint;
    function CanWalkTo(const aFrom, aTo: TKMPoint): Boolean; virtual;
    function DestinationReached(aX, aY: Word): Boolean; virtual;
    function IsWalkableTile(aX, aY: Word): Boolean; virtual;
    function MovementCost(aFromX, aFromY, aToX, aToY: Word): Word; virtual;
    function HeapCmp(A,B: Pointer): Boolean;
  public
    Heap: THeap;
    constructor Create;
    destructor Destroy; override;

    function Route_Make(aLocA, aLocB: TKMPoint; aPass: TPassabilitySet; aDistance: Single; aTargetHouse: TKMHouse; NodeList: TKMPointList; aWeightRoutes: Boolean = True): Boolean;
    function Route_MakeAvoid(aLocA, aLocB: TKMPoint; aPass: TPassabilitySet; aDistance: Single; aTargetHouse: TKMHouse; NodeList: TKMPointList): Boolean;
    function Route_ReturnToWalkable(aLocA, aLocB: TKMPoint; aTargetWalkConnect: TWalkConnect; aTargetNetwork: Byte; aPass: TPassabilitySet; NodeList: TKMPointList): Boolean;
    procedure UpdateState;
  end;


implementation


{ TPathFinding }
constructor TPathFinding.Create;
var
  I: Integer;
begin
  inherited;

  Heap := THeap.Create;
  Heap.Cmp := HeapCmp;

  if CACHE_PATHFINDING then
  for I := 0 to PATH_CACHE_MAX - 1 do
    fCache[I].Route := TKMPointList.Create;
end;


destructor TPathFinding.Destroy;
var
  I: Integer;
begin
  Reset;
  Heap.Free;

  if CACHE_PATHFINDING then
  for I := 0 to PATH_CACHE_MAX - 1 do
    FreeAndNil(fCache[I].Route);

  inherited;
end;


function TPathFinding.HeapCmp(A, B: Pointer): Boolean;
begin
  if A = nil then
    Result := True
  else
    Result := (B = nil) or (TANode(A).Estim + TANode(A).CostTo < TANode(B).Estim + TANode(B).CostTo);
end;


//Find a route from A to B which meets aPass Passability
//Results should be written as NodeCount of waypoint nodes to Nodes
function TPathFinding.Route_Make(aLocA, aLocB: TKMPoint; aPass:TPassabilitySet; aDistance:single; aTargetHouse:TKMHouse; NodeList:TKMPointList; aWeightRoutes: Boolean = True): Boolean;
begin
  Result := False;

  fLocA := aLocA;
  fLocB := aLocB;
  fPass := aPass;
  fTargetNetwork := 0;
  fTargetWalkConnect := wcWalk;
  fDistance := aDistance;
  fIsInteractionAvoid := False;
  fTargetHouse := aTargetHouse;
  fWeightRoutes := aWeightRoutes and DO_WEIGHT_ROUTES;
  if fTargetHouse = nil then
    fDestination := dp_Location
  else
    fDestination := dp_House;

  //Try to find similar route in cache and reuse it
  if CACHE_PATHFINDING and TryRouteFromCache(NodeList) then
    Result := True
  else
  if MakeRoute then
  begin
    ReturnRoute(NodeList);
    Result := True;
  end else
    NodeList.Clear;
end;


//We are using Interaction Avoid mode (go around busy units)
function TPathFinding.Route_MakeAvoid(aLocA, aLocB: TKMPoint; aPass:TPassabilitySet; aDistance:single; aTargetHouse:TKMHouse; NodeList:TKMPointList):boolean;
begin
  Result := False;

  fLocA := aLocA;
  fLocB := aLocB;
  fPass := aPass;
  fTargetNetwork := 0;
  fTargetWalkConnect := wcWalk;
  fDistance := aDistance;
  fIsInteractionAvoid := True;
  fTargetHouse := aTargetHouse;
  if fTargetHouse = nil then
    fDestination := dp_Location
  else
    fDestination := dp_House;

  if MakeRoute then
  begin
    ReturnRoute(NodeList);
    Result := True;
  end;
end;


//Even though we are only going to a road network it is useful to know where our target is so we start off in the right direction (makes algorithm faster/work over long distances)
function TPathFinding.Route_ReturnToWalkable(aLocA, aLocB: TKMPoint; aTargetWalkConnect:TWalkConnect; aTargetNetwork:byte; aPass:TPassabilitySet; NodeList:TKMPointList): Boolean;
begin
  Result := False;

  fLocA := aLocA;
  fLocB := aLocB;
  fPass := aPass; //Should be unused here
  fTargetNetwork := aTargetNetwork;
  fTargetWalkConnect := aTargetWalkConnect;
  fDistance := 0;
  fIsInteractionAvoid := False;
  fTargetHouse := nil;
  fDestination := dp_Passability;

  if MakeRoute then
  begin
    ReturnRoute(NodeList);
    Result := True;
  end else
    NodeList.Clear;
end;


function TPathFinding.CanWalkTo(const aFrom, aTo: TKMPoint): Boolean;
begin
  Result := fTerrain.CanWalkDiagonaly(aFrom, aTo);
end;


function TPathFinding.IsWalkableTile(aX, aY: Word): Boolean;
begin
  //If cell meets Passability then estimate it
  Result := (fPass * fTerrain.Land[aY,aX].Passability) <> [];
end;


//How much it costs to move From -> To
function TPathFinding.MovementCost(aFromX, aFromY, aToX, aToY: Word): Word;
begin
  if Abs(aFromX-aToX) > Abs(aFromY-aToY) then
    Result := Abs(aFromX-aToX) * 10 + Abs(aFromY-aToY) * 4
  else
    Result := Abs(aFromY-aToY) * 10 + Abs(aFromX-aToX) * 4;

  //Do not add extra cost if the tile is the target, as it can cause a longer route to be chosen
  if (aToX <> fLocB.X) or (aToY <> fLocB.Y) then
  begin
    if fWeightRoutes and (fTerrain.Land[aToY,aToX].IsUnit <> nil) then
      Inc(Result, 10); //Unit = 1 extra tile
    if fIsInteractionAvoid and fTerrain.TileIsLocked(KMPoint(aToX,aToY)) then
      Inc(Result, 500); //In interaction avoid mode, working unit = 50 tiles
  end;
end;


function TPathFinding.DestinationReached(aX, aY: Word): Boolean;
begin
  case fDestination of
    dp_Location:    Result := KMLengthDiag(KMPoint(aX, aY), fLocB) <= fDistance;
    dp_Passability: Result := fTerrain.GetConnectID(fTargetWalkConnect, KMPoint(aX, aY)) = fTargetNetwork;
    dp_House:       Result := fTargetHouse.InReach(KMPoint(aX, aY), fDistance);
    else            Result := true;
  end;
end;


procedure TPathFinding.Reset;
var
  I,K: Integer;
begin
  for I := 0 to High(ORef) do
  for K := 0 to High(ORef[I]) do
  if ORef[I,K] <> nil then
  begin
    ORef[I,K].Free;
    ORef[I,K] := nil;
  end;
end;


function TPathFinding.MakeRoute: Boolean;
const c_closed = 65535;
var
  N: TANode;
  X, Y: Integer;
  NewCost: Integer;
begin
  //Clear previous data
  Reset;
  SetLength(ORef, fTerrain.MapY+1, fTerrain.MapX+1);

  //Initialize first element
  N := TANode.Create;
  ORef[fLocA.Y, fLocA.X] := N;
  N.X       := fLocA.X;
  N.Y       := fLocA.Y;
  N.Estim   := (abs(fLocB.X-fLocA.X) + abs(fLocB.Y-fLocA.Y)) * 10;
  N.Parent  := nil;

  //Seed
  MinN := N;

  while (MinN <> nil) and not DestinationReached(MinN.X, MinN.Y) do
  begin

    MinN.Estim := c_closed;

    //Check all surrounding cells and issue costs to them
    for y := Math.max(MinN.Y-1,1) to Math.min(MinN.Y+1, fTerrain.MapY-1) do
    for x := Math.max(MinN.X-1,1) to Math.min(MinN.X+1, fTerrain.MapX-1) do
    if ORef[y,x] = nil then //Cell is new
    begin
      if CanWalkTo(KMPoint(MinN.X, MinN.Y), KMPoint(x,y)) then
      begin

        N := TANode.Create;
        ORef[y,x] := N;
        N.X := x;
        N.Y := y;
        N.Parent := MinN;

        if IsWalkableTile(X, Y) then
        begin
          N.CostTo := MinN.CostTo + MovementCost(MinN.X, MinN.Y, X, Y);
          N.Estim := (abs(x-fLocB.X) + abs(y-fLocB.Y)) * 10; //Use Estim even if destination is Passability, as it will make it faster. Target should be in the right direction even though it's not our destination.
          Heap.Push(N);
        end
        else //If cell doen't meets Passability then mark it as Closed
          N.Estim := c_closed;

      end;
    end
    else //Else cell is old
    begin

      //If route through new cell is shorter than ORef[y,x] then
      if ORef[y,x].Estim <> c_closed then
      if CanWalkTo(KMPoint(MinN.X, MinN.Y), KMPoint(x,y)) then
      begin
        NewCost := MovementCost(MinN.X, MinN.Y, X, Y);
        if MinN.CostTo + NewCost < ORef[y,x].CostTo then
        begin
          ORef[y,x].Parent := MinN;
          ORef[y,x].CostTo := MinN.CostTo + NewCost;
        end;
      end;
    end;

    //Find next cell with least (Estim+CostTo)
    MinN := Heap.Pop;
  end;

  //Route found, no longer need the lookups
  Heap.Clear;

  Result := DestinationReached(MinN.X, MinN.Y);
  //Assert(fMinCost.Cost<>65535, 'FloodFill test failed and there''s no possible route A-B');
end;


procedure TPathFinding.ReturnRoute(NodeList: TKMPointList);
var
  N: TANode;
begin
  NodeList.Clear;

  //Assemble the route
  N := MinN;
  while N <> nil do
  begin
    NodeList.AddEntry(KMPoint(N.X, N.Y));
    N := N.Parent;
  end;

  //Reverse the list, since path is assembled LocB > LocA
  NodeList.Inverse;

  //Cache long paths
  if CACHE_PATHFINDING and (NodeList.Count > 20) then
    AddToCache(NodeList);
end;


//Cache the route incase it is needed soon
procedure TPathFinding.AddToCache(NodeList: TKMPointList);
var
  I: Integer;
  Best: Integer;
begin
  //Find cached route with least weight and replace it
  Best := 0;
  for I := 1 to PATH_CACHE_MAX - 1 do
  if fCache[I].Weight < fCache[Best].Weight then
    Best := I;

  fCache[Best].Weight := PATH_CACHE_INIT_WEIGHT;
  fCache[Best].Pass := fPass;
  fCache[Best].Route.Copy(NodeList);
end;


function TPathFinding.TryRouteFromCache(NodeList: TKMPointList): Boolean;
  //Check if we can straightly walk to Route from our loc
  function NearStart(const aRoute: TKMPointList): Boolean;
  begin
    Result := (KMLengthDiag(aRoute[0], fLocB) < 2)
           or (KMLengthDiag(aRoute[1], fLocB) < 2)
           or (KMLengthDiag(aRoute[2], fLocB) < 2);
  end;
  //Check if we can straightly walk to target from any of last Routes points
  function NearEnd(const aRoute: TKMPointList): Boolean;
  begin
    Result := (KMLengthDiag(aRoute[aRoute.Count-1], fLocB) < 2)
           or (KMLengthDiag(aRoute[aRoute.Count-2], fLocB) < 2)
           or (KMLengthDiag(aRoute[aRoute.Count-3], fLocB) < 2);
  end;
var
  I,K: Integer;
  BestStart, BestEnd: Word;
  NewL, BestL: Single;
begin
  Result := False;

  for I := 0 to PATH_CACHE_MAX - 1 do
  if (fCache[I].Route.Count > 0)
  and (fCache[I].Pass = fPass) then
  begin

    //Check if route starts within reach
    BestL := MaxSingle;
    for K := 0 to 5 do
    begin
      NewL := KMLengthDiag(fLocA, fCache[I].Route[K]);
      if NewL < 2 then
      begin
        BestStart := K;
        BestL := NewL;
      end;
    end;

    if BestL >= 2 then Continue;

    //Check if route ends within reach
    BestL := MaxSingle;
    for K := fCache[I].Route.Count - 1 downto fCache[I].Route.Count - 5 do
    begin
      NewL := KMLengthDiag(fLocB, fCache[I].Route[K]);
      if NewL < 2 then
      begin
        BestEnd := K;
        BestL := NewL;
      end;
    end;

    if BestL >= 2 then Continue;

    //Assemble the route
    NodeList.Clear;
    NodeList.AddEntry(fLocA);
    for K := BestStart to BestEnd do
      NodeList.AddEntry(fCache[I].Route[K]);
    NodeList.AddEntry(fLocB);

    //Mark the cached route as more useful
    Inc(fCache[I].Weight);

    Result := True;
    Exit;
  end;
end;


procedure TPathFinding.UpdateState;
var
  I: Integer;
begin
  if CACHE_PATHFINDING then
  for I := 0 to PATH_CACHE_MAX - 1 do
    fCache[I].Weight := Max(fCache[I].Weight - 1, 0);
end;


end.