unit KM_UnitActionGoInOut;
interface
uses Classes, KM_Defaults, KromUtils, KM_Utils, KM_CommonTypes, KM_Player, KM_Units, SysUtils, Math;


{This is a simple action making unit go inside/outside of house}
type
  TUnitActionGoInOut = class(TUnitAction)
    private
        fStep:single;
        fDirection:TGoInDirection;
        fHouseType:THouseType;
        fDoor:TKMPointF;
        fStreet:TKMPoint;
//        fStartX:single;
        fHasStarted, fWaitingForPush:boolean;
    public
        constructor Create(aAction: TUnitActionType; aDirection:TGoInDirection; aHouseType:THouseType=ht_None);
        procedure Execute(KMUnit: TKMUnit; TimeDelta: single; out DoEnd: Boolean); override;
        procedure Save(SaveStream:TMemoryStream); override;
    end;


implementation
uses KM_Houses, KM_Game, KM_PlayersCollection, KM_Terrain, KM_Viewport, KM_UnitActionStay, KM_UnitActionWalkTo;


constructor TUnitActionGoInOut.Create(aAction: TUnitActionType; aDirection:TGoInDirection; aHouseType:THouseType=ht_None);
begin
  Inherited Create(aAction);
  fActionName := uan_GoInOut;
  fDirection      := aDirection;
  fHouseType      := aHouseType;
  fHasStarted     := false;
  fWaitingForPush := false;
  
  if fDirection = gd_GoInside then
    fStep := 1  //go Inside (one cell up)
  else
    fStep := 0; //go Outside (one cell down)
end;


procedure TUnitActionGoInOut.Execute(KMUnit: TKMUnit; TimeDelta: single; out DoEnd: Boolean);
var Distance:single; TempUnit: TKMUnit;
  function ValidTile(LocX,LocY:word; aUnit:TKMUnit):boolean; //using X,Y looks more clear
  begin
    Result := fTerrain.TileInMapCoords(LocX,LocY) and (fTerrain.CheckPassability(KMPoint(LocX,LocY),canWalk));
    if Result then
    Result := (fTerrain.Land[LocY,LocX].IsUnit = 0) or ((aUnit <> nil)
          and (aUnit.GetUnitAction is TUnitActionStay) and (aUnit.GetUnitActionType = ua_Walk)
          and (not TUnitActionStay(aUnit.GetUnitAction).Locked))
  end;
begin
  DoEnd:= False;
  TimeDelta:=0.1;

  if not fHasStarted then //Set Door and Street locations
  begin

    fDoor := KMPointF(KMUnit.GetPosition.X, KMUnit.GetPosition.Y - fStep);
    fStreet := KMPoint(KMUnit.GetPosition.X, KMUnit.GetPosition.Y + 1 - round(fStep));
    if byte(fHouseType) in [1..length(HouseDAT)] then
      fDoor.X := fDoor.X + (HouseDAT[byte(fHouseType)].EntranceOffsetXpx/4)/CELL_SIZE_PX;


    if fDirection=gd_GoInside then
    begin
      KMUnit.Direction := dir_N;  //one cell up
      KMUnit.Thought := th_None;
      KMUnit.NextPosition := KMPoint(KMUnit.GetPosition.X,KMUnit.GetPosition.Y-1);
      fTerrain.UnitWalk(KMUnit.GetPosition, KMUnit.NextPosition);
      if (KMUnit.GetHome<>nil) and (KMUnit.GetHome.GetHouseType=ht_Barracks) then //Units home is barracks
        TKMHouseBarracks(KMUnit.GetHome).RecruitsInside := TKMHouseBarracks(KMUnit.GetHome).RecruitsInside + 1;
    end;

    if fDirection=gd_GoOutSide then
    begin //Attempt to find a tile bellow the door we can walk to. Otherwise we can push idle units away.
      TempUnit := fPlayers.UnitsHitTest(fStreet.X,fStreet.Y);
      if ValidTile(fStreet.X,fStreet.Y,TempUnit) then
        //fStreet.X := fStreet.X
      else
      begin
        TempUnit := fPlayers.UnitsHitTest(fStreet.X-1,fStreet.Y);
        if ValidTile(fStreet.X-1,fStreet.Y,TempUnit) then
          fStreet.X := fStreet.X - 1
        else
        begin
          TempUnit := fPlayers.UnitsHitTest(fStreet.X+1,fStreet.Y);
          if ValidTile(fStreet.X+1,fStreet.Y,TempUnit) then
            fStreet.X := fStreet.X + 1
          else
            exit; //Do not exit the house if all street tiles are blocked by non-idle units, just wait
        end;
      end;

      if (TempUnit <> nil)
        and (TempUnit.GetUnitAction is TUnitActionStay) and (TempUnit.GetUnitActionType = ua_Walk)
        and (not TUnitActionStay(TempUnit.GetUnitAction).Locked) then
      begin
        TempUnit.SetActionWalk(TempUnit, fTerrain.GetOutOfTheWay(TempUnit.GetPosition,KMUnit.GetPosition,canWalk));
        TUnitActionWalkTo(TempUnit.GetUnitAction).SetPushedValues;
      end;

      if (fTerrain.Land[fStreet.Y,fStreet.X].IsUnit <> 0) then
      begin
        fWaitingForPush := true;
        fHasStarted:=true;
        exit; //Wait until my push request is delt with before we move out
      end;

      //All check done and unit can walk out now
      KMUnit.Direction := KMGetDirection(KMPointRound(fDoor) ,fStreet);
      KMUnit.NextPosition := fStreet;
      fTerrain.UnitWalk(KMUnit.GetPosition,KMUnit.NextPosition);
      if (KMUnit.GetHome<>nil)and(KMUnit.GetHome.GetHouseType=ht_Barracks) then //Unit home is barracks
        TKMHouseBarracks(KMUnit.GetHome).RecruitsInside:=TKMHouseBarracks(KMUnit.GetHome).RecruitsInside - 1;
    end;

    fHasStarted:=true;
  end;

  if fWaitingForPush then
  begin
    if (fTerrain.Land[fStreet.Y,fStreet.X].IsUnit = 0) then
    begin
      fWaitingForPush := false;
      KMUnit.Direction := KMGetDirection(KMPointRound(fDoor) ,fStreet);
      KMUnit.NextPosition := fStreet;
      fTerrain.UnitWalk(KMUnit.GetPosition,KMUnit.NextPosition);
      if (KMUnit.GetHome<>nil)and(KMUnit.GetHome.GetHouseType=ht_Barracks) then //Unit home is barracks
        TKMHouseBarracks(KMUnit.GetHome).RecruitsInside:=TKMHouseBarracks(KMUnit.GetHome).RecruitsInside - 1;
    end
    else exit; //Wait until my push request is delt with before we move out
  end;

  Distance:= TimeDelta * KMUnit.GetSpeed;
  fStep := fStep - Distance * shortint(fDirection);
  KMUnit.PositionF := KMPointF(Mix(fStreet.X,fDoor.X,fStep),Mix(fStreet.Y,fDoor.Y,fStep));
  KMUnit.SetVisibility := fStep >= 0.3; //Make unit invisible when it's inside of House

  if (fStep<=0)or(fStep>=1) then
  begin
    DoEnd:=true;
    if fDirection = gd_GoInside then
      KMUnit.PositionF := fDoor
    else
      KMUnit.PositionF := KMPointF(fStreet.X,fStreet.Y);
  end
  else
    inc(KMUnit.AnimStep);
end;


procedure TUnitActionGoInOut.Save(SaveStream:TMemoryStream);
begin
  inherited;
  SaveStream.Write(fStep,4);
  SaveStream.Write(fDirection,4);
  SaveStream.Write(fHouseType,4);
  SaveStream.Write(fDoor,8);
  SaveStream.Write(fStreet,4);
  SaveStream.Write(fHasStarted,4);
  SaveStream.Write(fWaitingForPush,4);
end;


end.
