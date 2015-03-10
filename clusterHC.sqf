/*
* clusterHC.sqf
*
* In the mission editor, name the Headless Clients "HC", "HC2", "HC3" without the quotes
*
* In the mission init.sqf, spawn clusterHC.sqf with:
* [] spawn compile preprocessFileLineNumbers "clusterHC.sqf"
*
* It seems that the dedicated server anqd headless client processes never use more than 20-22% CPU each.
* With a dedicated server and 3 headless clients, that's about 88% CPU with 10-12% left over.  Far more efficient use of your processing power.
* 
* hasLineOfSight function provided by:
*   SaOK - http://forums.bistudio.com/showthread.php?135252-Line-Of-Sight-(Example-Thread)&highlight=los
*   TPW MODS: http://forums.bistudio.com/showthread.php?164304-TPW-MODS-enhanced-realism-immersion-for-Arma-3-SP
*
*/

// These variables may be manipulated
rebalanceTimer = 60;  // Rebalance sleep timer in seconds
cleanUpThreshold = 5; // Threshold of number of dead bodies + destroyed vehicles before forcing a clean up
fpsThreshold = 25; // Each Player's FPS threshold to trigger caching AI groups/units the player has no line of sight to, starting from the furthest from the player and working closer
maxDistance = 0; // Set to 0 for no maximum distance (technically, defaults to 20km)
enableDiagPanel = true; // Enable or disable showing real time debug information

diag_log "clusterHC: Started";
private ["_diagPanel", "_simUnits", "_cacheUnits"];

///////////////////////// START PLAYER CODE /////////////////////////
_diagPanel = {
  private ["_panel", "_tmp"];
  _panel = {
    _tmp = 0;
    { if (!simulationEnabled _x) then {_tmp = _tmp + 1;}; } forEach (allUnits);
    hintSilent composeText [parseText "<t align='center'><t font='EtelkaMonospaceProBold'><t size='1.5'><t color='#CC0000'><t underline='true'>clusterHC</t></t></t><br/><t size='1.0'>Diagnostic Panel</t></t></t><br/>", lineBreak,
                            format ["FPS: %1", diag_fps], lineBreak,
                            format ["FPSMin: %1", diag_fps], lineBreak,
                            format ["Number of Units: %1", count allUnits], lineBreak,
                            format ["BLUFOR: %1", west countSide allUnits], lineBreak,
                            format ["OPFOR: %1", east countSide allUnits], lineBreak,
                            format ["CIV: %1", civilian countSide allUnits], lineBreak,
                            format ["Cached: %1", _tmp]];
  };
  while {true} do { if (enableDiagPanel) then { _indexEH = addMissionEventHandler ["Draw3D", _panel]; sleep 1; removeMissionEventHandler ["Draw3D", _indexEH]; } else {hint ""; waitUntil{enableDiagPanel};}; };
};

_simUnits = {
  _enableSim = {
    if (diag_fps >= fpsThreshold) then {
      if (maxDistance == 0) then { maxDistance = 20000; };
      // { { if (diag_fps >= fpsThreshold) then { if (!simulationEnabled _x) then { _x enableSimulation true; }; }; } forEach (units _x); } forEach (allGroups);
      {
        if (diag_fps >= fpsThreshold) then {
          if (typeName _x != "OBJECT") then {diag_log format ["clusterHC: _simUnits - typeName _x == %1", typeName _x];};
          if (typeName _x == "TEAM_MEMBER") then {_x = agent _x;};
          if (!simulationEnabled _x) then { _x enableSimulation true; }; };
      } forEach (player nearEntities maxDistance);
    };
  };
  // while {true} do { _indexEH = addMissionEventHandler ["Draw3D", _enableSim]; sleep 1; removeMissionEventHandler ["Draw3D", _indexEH]; };
  while {true} do { ["clusterHC_EH_cleanUp", "onEachFrame", _enableSim] spawn BIS_fnc_addStackedEventHandler; sleep 1; ["clusterHC_EH_cleanUp", "onEachFrame"] spawn BIS_fnc_removeStackedEventHandler; };    
};

getGroupDistances = {
  private ["_groupDistancesInside"];
  _groupDistancesInside = [ ["", -1] ];

  {
    private ["_groupLeader", "_currentUnit", "_tmpDistance"];
    _groupLeader = leader _x;
    if ((typeName (_this select 0)) == "GROUP") then { _currentUnit = leader (_this select 0); };
    if (isNil "_currentUnit") then { _currentUnit = player };
    _tmpDistance = (getPosASL _currentUnit) distance (getPosASL _groupLeader);
    if (isNil "_tmpDistance") then { _tmpDistance = -1; };
    _groupDistancesInside = _groupDistancesInside + [ [groupID _x, _tmpDistance] ];
  } forEach (allGroups);

  _groupDistancesInside
};

getFurthestElement = {
  private ["_groupDistancesInside", "_furthestElementInside", "_currentDistance", "_numGroupDistances"];
  _groupDistancesInside = _this;
  _furthestElementInside = 0;
  _currentDistance = -1;
  _numGroupDistances = count _groupDistancesInside;
  for "_i" from 0 to _numGroupDistances step 1 do {
    _currentDistance = ((_groupDistancesInside select _i) select 1);
    if (isNil "_currentDistance") then { _currentDistance = -1; };
    
    if ( _currentDistance > 0 ) then {
      if ( ((_groupDistancesInside select _i) select 1) > ((_groupDistancesInside select _furthestElementInside) select 1) ) then { _furthestElementInside = _i; };
    };
  };

  _furthestElementInside
};

hasLineOfSight = {
  private ["_thePlayer", "_theUnit", "_eyeDV", "_eyeD", "_dirTo", "_ang", "_eyePlayer", "_eyeUnit", "_tInt", "_lInt", "_rc"];
  _thePlayer = _this select 0;
  _theUnit = _this select 1;
  _eyeDV = eyeDirection _thePlayer;
  _eyeD = ((_eyeDV select 0) atan2 (_eyeDV select 1));
  _dirTo = [_thePlayer, _theUnit] call BIS_fnc_dirTo;
  waitUntil {!isNil "_dirTo"};
  _ang = abs (_dirTo - _eyeD);
  _eyePlayer = eyePos _thePlayer;
  _eyeUnit = eyePos _theUnit;
  _tInt = terrainIntersectASL [_eyePlayer, _eyeUnit];
  _lInt = lineIntersects [_eyePlayer, _eyeUnit];

  _rc = false;
  if ( ((_ang > 120) && (_ang < 240)) && {!(_lInt) && !(_tInt)} ) then { _rc = true; };

  _rc
};

_cacheUnits = {
  private ["_getGroupDistances", "_getFurthestElement", "_hasLineOfSight", "_groupDistances", "_cacheCount", "_furthestElement", "_hasClearLoS"];
  _getGroupDistances = getGroupDistances;
  _getFurthestElement = getFurthestElement;
  _hasLineOfSight = hasLineOfSight;

  waitUntil {diag_fps <= fpsThreshold};  
  
  _groupDistances = call _getGroupDistances;
  waitUntil {!isNil "_groupDistances"};

  while {true} do {
    waitUntil {diag_fps <= fpsThreshold};
    
    _cacheCount = 0;
    { if (_x select 1 == -1) then { _cacheCount = _cacheCount + 1; }; } forEach (_groupDistances);
    
    if ( _cacheCount == ((count _groupDistances) - 1)) then { _groupDistances = call _getGroupDistances; waitUntil {!isNil "_groupDistances"}; };
    
    _furthestElement = _groupDistances call _getFurthestElement;
    waitUntil {!isNil "_furthestElement"};

    if ( ((_groupDistances select _furthestElement) select 1) >= 0 ) then {
      {
        if (groupID _x == (_groupDistances select _furthestElement) select 0) then {
          {
            if (!isPlayer _x) then {
              // if (typeName _x != "OBJECT") then {diag_log format ["clusterHC: _cacheUnits - typeName _x == %1", typeName _x];};
              // if (typeName _x == "TEAM_MEMBER") then {_x = agent _x;};
              _hasClearLoS = [player, _x] call _hasLineOfSight;
              waitUntil {!isNil "_hasClearLoS"};

              if ( !(_hasClearLoS) ) then { if (simulationEnabled _x) then { _x enableSimulation false; }; };
              // else { if (!simulationEnabled _x) then { _x enableSimulation true; }; };
            };
          } forEach (units _x);

          _groupDistances set [_furthestElement, ["", -1]];
        };
      } forEach (allGroups);
    };
  };
};

// Player clients
if (!isServer && hasInterface) exitWith {
  waitUntil {!isNull player};

  systemChat "Powered by clusterHC";

  [] spawn _diagPanel;
  [] spawn _simUnits;
  [] spawn _cacheUnits;
};
///////////////////////// END PLAYER CODE /////////////////////////

///////////////////////// START SERVER/HC CODE /////////////////////////
waitUntil {!isNil "HC"};
waitUntil {!isNull HC};

// Leave these variables as-is, we'll auto set them later
private ["_HC_ID", "_HC2_ID", "_HC3_ID"];
_HC_ID = -1; // Will become the Client ID of HC
_HC2_ID = -1; // Will become the Client ID of HC2
_HC3_ID = -1; // Will become the Client ID of HC3
HCSimArray = []; // Will become an array of groups HC owns. Server broadcasts this to HC for simulations
HC2SimArray = []; // Will become an array of groups HC2 owns. Server broadcasts this to HC2 for simulations
HC3SimArray = []; // Will become an array of groups HC3 owns. Server broadcasts this to HC3 for simulations

private "_cacheUnitsHC";

_cacheUnitsHC = {
  private ["_getGroupDistances", "_getFurthestElement", "_hasLineOfSight"];
  _getGroupDistances = getGroupDistances;
  _getFurthestElement = getFurthestElement;
  _hasLineOfSight = hasLineOfSight;

  waitUntil {diag_fps <= fpsThreshold};
  while {true} do {
    waitUntil {diag_fps <= fpsThreshold};

    private ["_thisSimArray", "_numThisSimArray"];

    switch (profileName) do {
      case "HC": { _thisSimArray = HCSimArray; };
      case "HC2": { _thisSimArray = HC2SimArray; };
      case "HC3": { _thisSimArray = HC3SimArray; };
      default {diag_log "clusterHC: [ERROR] HC Profile Name Not Recognized"; _thisSimArray = []; };
    };

    _numThisSimArray = count _thisSimArray;
    for "_i" from 0 to _numThisSimArray step 1 do {
      private ["_groupDistances", "_furthestElement", "_currentLeader"];
      _groupDistances = [_thisSimArray select _i] call _getGroupDistances;
      waitUntil {!isNil "_groupDistances"};

      _furthestElement = _groupDistances call _getFurthestElement;
      waitUntil {!isNil "_furthestElement"};

      _currentLeader = leader (_thisSimArray select _i);
      if (!isNil "_currentLeader") then {
        if ( ((_groupDistances select _furthestElement) select 1) >= 0 ) then {
          {
            if (groupID _x == (_groupDistances select _furthestElement) select 0) then {
              {
                if (!isPlayer _x) then {
                  // if (typeName _x != "OBJECT") then {diag_log format ["clusterHC: _cacheUnitsHC - typeName _x == %1", typeName _x];};
                  // if (typeName _x == "TEAM_MEMBER") then {_x = agent _x;};
                  private ["_hasClearLoS"];
                  _hasClearLoS = [_currentLeader, _x] call _hasLineOfSight;
                  waitUntil {!isNil "_hasClearLoS"};

                  if ( !(_hasClearLoS) ) then { if (simulationEnabled _x) then { _x enableSimulation false; }; };
                  // else { if (!simulationEnabled _x) then { _x enableSimulation true; }; };
                };
              } forEach (units _x);

              _groupDistances set [_furthestElement, ["", -1]];
            };
          } forEach (allGroups);
        };
      };
    };
  };
};

// diag_log format["clusterHC: First pass will begin in %1 seconds", rebalanceTimer];

// Only HCs should run this infinite loop to re-enable simulations for AI that it owns
if (!isServer && !hasInterface) exitWith {
  [] spawn _simUnits;
  [] spawn _cacheUnitsHC;
};
///////////////////////// END SERVER/HC CODE /////////////////////////

///////////////////////// START SERVER ONLY CODE /////////////////////////
// Function _cleanUp
// Example: [] spawn _cleanUp;
private "_cleanUp";
_cleanUp = {
  // Force clean up dead bodies and destroyed vehicles
  if (count allDead > cleanUpThreshold) then {
    private ["_numDeleted"];    
    _numDeleted = 0;
    {
      deleteVehicle _x;

      _numDeleted = _numDeleted + 1;
    } forEach (allDead);

    // diag_log format ["clusterHC: Cleaned up %1 dead bodies/destroyed vehicles", _numDeleted];
  };
};

// Spawn _cleanUp function in a seperate thread
["clusterHC_EH_cleanUp", "onEachFrame", _cleanUp] spawn BIS_fnc_addStackedEventHandler;

_indexEHMPKilledArray = [ [(allUnits select 0), -1] ];
_indexEHLocalArray = [ [(allUnits select 0), -1] ];

while {true} do {
  { if (!isPlayer _x) then { _x enableSimulation false; }; } forEach (allUnits);

  // Rebalance every rebalanceTimer seconds to avoid hammering the server
  sleep rebalanceTimer;

  // if (count (_indexEHMPKilledArray select 1) > 2) then { { (_x select 0) removeMPEventHandler ["MPKilled", (_x select 1)]; } forEach (_indexEHMPKilledArray); };
  if (count _indexEHMPKilledArray > 1) then { { if (_forEachIndex > 0) then { (_x select 0) removeMPEventHandler ["MPKilled", (_x select 1)]; }; } forEach (_indexEHMPKilledArray); };
  if (count _indexEHLocalArray > 1) then { { if (_forEachIndex > 0) then { (_x select 0) removeMPEventHandler ["Local", (_x select 1)]; }; } forEach (_indexEHLocalArray); };
  
  _indexEHMPKilledArray = [ [(allUnits select 0), -1] ];
  _indexEHLocalArray = [ [(allUnits select 0), -1] ];
  {
    _indexMPKilled = _x addMPEventHandler ["MPKilled", { [_this select 0] spawn { sleep 3; (_this select 0) enableSimulation false; };}]; 
    _indexEHMPKilledArray = _indexEHMPKilledArray + [[_x, _indexMPKilled]];
    _indexMPLocal = _x addMPEventHandler ["Local", { if (_this select 1) then {(_this select 0) enableSimulation true;} }];
    _indexEHLocalArray = _indexEHLocalArray + [[_x, _indexMPLocal]];
  } forEach (allUnits);

  // _numSimulating = 0;
  // { if (simulationEnabled _x) then { _numSimulating = _numSimulating + 1; }; } forEach (allUnits);
  // if (_numSimulating > 0) then { diag_log format ["clusterHC: [INFO] [Server] Currently simulating %1 entities", _numSimulating]; };

  // Do not enable load balancing unless more than one HC is present
  // Leave this variable false, we'll enable it automatically under the right conditions
  _loadBalance = false;

   // Get HC Client ID else set variables to null
   try {
    _HC_ID = owner HC;

    if (_HC_ID > 2) then {
      // diag_log format ["clusterHC: Found HC with Client ID %1", _HC_ID];
    } else { 
      diag_log "clusterHC: [WARN] HC disconnected";

      HC = objNull;
      _HC_ID = -1;
    };
  } catch { diag_log format ["clusterHC: [ERROR] [HC] %1", _exception]; HC = objNull; _HC_ID = -1; };

  // Get HC2 Client ID else set variables to null
  if (!isNil "HC2") then {
    try {
      _HC2_ID = owner HC2;

      if (_HC2_ID > 2) then {
        // diag_log format ["clusterHC: Found HC2 with Client ID %1", _HC2_ID];
      } else { 
        diag_log "clusterHC: [WARN] HC2 disconnected";
        
        HC2 = objNull;
        _HC2_ID = -1;
      };
    } catch { diag_log format ["clusterHC: [ERROR] [HC2] %1", _exception]; HC2 = objNull; _HC2_ID = -1; };
  };

  // Get HC3 Client ID else set variables to null
  if (!isNil "HC3") then {
    try {
      _HC3_ID = owner HC3;

      if (_HC3_ID > 2) then {
        // diag_log format ["clusterHC: Found HC3 with Client ID %1", _HC3_ID];
      } else { 
        diag_log "clusterHC: [WARN] HC3 disconnected";
        
        HC3 = objNull;
        _HC3_ID = -1;
      };
    } catch { diag_log format ["clusterHC: [ERROR] [HC3] %1", _exception]; HC3 = objNull; _HC3_ID = -1; };
  };

  // If no HCs present, wait for HC to rejoin
  if ( (isNull HC) && (isNull HC2) && (isNull HC3) ) then { waitUntil {!isNull HC}; };
  
  // Check to auto enable Round-Robin load balancing strategy
  if ( (!isNull HC && !isNull HC2) || (!isNull HC && !isNull HC3) || (!isNull HC2 && !isNull HC3) ) then { _loadBalance = true; };
  
  /*
  if ( _loadBalance ) then {
    diag_log "clusterHC: Starting load-balanced transfer of AI groups to HCs";
  } else {
    // No load balancing
    diag_log "clusterHC: Starting transfer of AI groups to HC";
  };
  */

  // Determine first HC to start with
  _currentHC = 0;

  if (!isNull HC) then { _currentHC = 1; } else { 
    if (!isNull HC2) then { _currentHC = 2; } else { _currentHC = 3; };
  };

  // Pass the AI
  _numTransfered = 0;
  {
    _swap = true;

    // If a player is in this group, don't swap to an HC
    { if (isPlayer _x) then { _swap = false; }; } forEach (units _x);

    // Enable simulations for the duration of the AI pass
    // { _x enableSimulation true; } forEach (units _x);

    // If load balance enabled, round robin between the HCs - else pass all to HC
    if ( _swap ) then {
      _rc = false;

      if ( _loadBalance ) then {
        switch (_currentHC) do {
          case 1: { _rc = _x setGroupOwner _HC_ID; if (!isNull HC2) then { _currentHC = 2; } else { _currentHC = 3; }; };
          case 2: { _rc = _x setGroupOwner _HC2_ID; if (!isNull HC3) then { _currentHC = 3; } else { _currentHC = 1; }; };
          case 3: { _rc = _x setGroupOwner _HC3_ID; if (!isNull HC) then { _currentHC = 1; } else { _currentHC = 2; }; };
          default { diag_log format["clusterHC: [ERROR] No Valid HC to pass to.  _currentHC = %1", _currentHC]; };
        };
      } else {
        switch (_currentHC) do {
          case 1: { _rc = _x setGroupOwner _HC_ID; };
          case 2: { _rc = _x setGroupOwner _HC2_ID; };
          case 3: { _rc = _x setGroupOwner _HC3_ID; };
          default { diag_log format["clusterHC: [ERROR] No Valid HC to pass to.  _currentHC = %1", _currentHC]; };
        };
      };

      // Disable simulations for this group after the pass
      // { if (!isPlayer _x) then { _x enableSimulation false; }; } forEach (units _x);

      // If the transfer was successful, count it for accounting and diagnostic information
      if ( _rc ) then { _numTransfered = _numTransfered + 1; };
    };
  } forEach (allGroups);

  // Divide up AI to delegate to HC(s)
  _numHC = 0;
  _numHC2 = 0;
  _numHC3 = 0;
  _HCSim = [];
  _HC2Sim = [];
  _HC3Sim = [];

  {
    switch (owner (leader _x)) do {
      case _HC_ID: { _HCSim = _HCSim + [_x]; _numHC = _numHC + 1; };
      case _HC2_ID: { _HC2Sim = _HC2Sim + [_x]; _numHC2 = _numHC2 + 1; };
      case _HC3_ID: { _HC3Sim = _HC3Sim + [_x]; _numHC3 = _numHC3+ 1; };
      case 1;
      case 2: { { _x enableSimulation true; } forEach (units _x); };
    };
  } forEach (allGroups);

  HCSimArray = _HCSim; _HC_ID publicVariableClient "HCSimArray";
  HC2SimArray = _HC2Sim; _HC2_ID publicVariableClient "HC2SimArray";
  HC3SimArray = _HC3Sim; _HC3_ID publicVariableClient "HC3SimArray";

  if (_numTransfered > 0) then {
    // More accounting/diagnostic information
    diag_log format ["clusterHC: Transfered %1 AI groups to HC(s)", _numTransfered];
    // if (_numHC > 0) then { diag_log format ["clusterHC: %1 AI groups currently on HC", _numHC]; };
    // if (_numHC2 > 0) then { diag_log format ["clusterHC: %1 AI groups currently on HC2", _numHC2]; };
    // if (_numHC3 > 0) then { diag_log format ["clusterHC: %1 AI groups currently on HC3", _numHC3]; };
  } else {
    // diag_log "clusterHC: No rebalance or transfers required this round";
  };

  // diag_log format ["clusterHC: %1 AI groups total across all HC(s)", (_numHC + _numHC2 + _numHC3)];
};
///////////////////////// END SERVER ONLY CODE /////////////////////////