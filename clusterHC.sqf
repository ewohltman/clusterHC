/*
* clusterHC.sqf
* https://github.com/AiE-Architect/clusterHC
*
* Author: [AiE]-Architect
*   In-Game: Sandman
*   Reddit: eulerfoiler
* 
* For Round-Robin Load Balancing:
* In the mission editor, name the Headless Clients "HC", "HC2", "HC3" without the quotes
*
* In the mission init.sqf, spawn clusterHC.sqf with:
* [] spawn compile preprocessFileLineNumbers "clusterHC.sqf"
*
* With or without HCs, players will use the caching system
*
* It seems that the dedicated server and headless client processes never use more than 20-22% CPU each.
* With a dedicated server and 3 headless clients, that's about 88% CPU with 10-12% left over.
* Far more efficient use of your processing power.
*
*/
diag_log "clusterHC: Started";

// These variables are recommended to not be changed and were observed to be optimal in tests
fpsThreshold = 20; // Each Player's FPS threshold to trigger caching AI groups/units starting with the furthest group
uncachedLimiter = 150; // Max number of AI to uncache when FPS < fpsThreshold
rebalanceTimer = 60; // AI:HC rebalance sleep timer in seconds

// These variables may be manipulated
// enableDiagPanel is a possible integration point for other systems/scripts by changing this global variable during runtime
enableDiagPanel = true; // Enable or disable showing real time debug information, can be changed during runtime
maxDistance = 0; // Set to 0 for no hard max distance to cache, should be greater than 500 (technically, 0 defaults to 30km)
corpseDecayTimer = (rebalanceTimer / 2); // All units corpse decay timer in seconds, must be less than rebalanceTimer

///////////////////////// START GLOBAL/GENERIC FUNCTIONS /////////////////////////
getGroupDistances = {
  private ["_groupDistancesInside"];
  _groupDistancesInside = [ [(allGroups select 0), -1] ];

  {
    private ["_groupLeader", "_currentUnit", "_tmpDistance"];
    _groupLeader = leader _x;
    if ((typeName (_this select 0)) == "GROUP") then { _currentUnit = leader (_this select 0); };
    if (isNil "_currentUnit") then { _currentUnit = player };
    _tmpDistance = (getPosASL _currentUnit) distance (getPosASL _groupLeader);
    if (isNil "_tmpDistance") then { _tmpDistance = -1; };
    _groupDistancesInside = _groupDistancesInside + [ [_x, _tmpDistance] ];
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

private "_simUnits";
maxDistanceScale = maxDistance;
_simUnits = {
  _enableSim = {
    private "_tmpFPS";
    _tmpFPS = diag_fps;

    if (!isServer && !hasInterface) exitWith {
      {
        if (diag_fps >= fpsThreshold) then { if (!simulationEnabled _x) then { _x enableSimulation true; }; };
      } forEach (allUnits);
    };

    private "_numUncached";
    _numUncached = 0;
    { if (simulationEnabled _x) then {_numUncached = _numUncached + 1;}; } forEach (allUnits);

    if (_tmpFPS < 15) then {maxDistanceScale = 100;}; // FPS 0 - 15
    if (_tmpFPS >= 15) then {maxDistanceScale = 300;}; // FPS 15 - 25
    if (_tmpFPS >= 25) then {maxDistanceScale = 500;}; // FPS 25 - 30
    if (_tmpFPS >= 30) then {maxDistanceScale = 1000;}; // FPS 30 - 35
    if (_tmpFPS >= 35) then {maxDistanceScale = maxDistance;}; // FPS >= 35
    if (maxDistanceScale == 0) then { maxDistanceScale = 30000; }; // Set default
    {
      if (_tmpFPS <= fpsThreshold) then {
        if (_numUncached < uncachedLimiter) then { if (!simulationEnabled _x) then {_x enableSimulation true; _numUncached = _numUncached + 1;}; };
      } else {
        if (!simulationEnabled _x) then { _x enableSimulation true; };
      };
    } forEach ((position player) nearEntities maxDistanceScale);
  };
  while {true} do { ["clusterHC_EH_cleanUp", "onEachFrame", _enableSim] call BIS_fnc_addStackedEventHandler; sleep 1; ["clusterHC_EH_cleanUp", "onEachFrame"] call BIS_fnc_removeStackedEventHandler; };
};
///////////////////////// END GLOBAL/GENERIC FUNCTIONS /////////////////////////

///////////////////////// START PLAYER FUNCTIONS /////////////////////////
private ["_diagPanel", "_cacheUnits"];
_diagPanel = {
  private "_panel";
  _panel = {
    private ["_numPlayers", "_cacheCountDiag"];
    _numPlayersDiag = 0;
    _cacheCountDiag = 0;
    { if (isPlayer _x) then {_numPlayersDiag = _numPlayersDiag + 1;} else { if (!simulationEnabled _x) then {_cacheCountDiag = _cacheCountDiag + 1;}; }; } forEach (allUnits);

    hintSilent composeText [parseText "<t align='center'><t font='EtelkaMonospaceProBold'><t size='1.5'><t color='#CC0000'><t underline='true'>clusterHC</t></t></t><br/><t size='1.0'>Diagnostic Panel</t></t></t><br/>", lineBreak,
                            format ["FPS: %1", diag_fps], lineBreak,
                            format ["FPSMin: %1", diag_fpsmin], lineBreak,
                            format ["Number of Units: %1", count allUnits], lineBreak,
                            format ["Number of Players: %1", _numPlayersDiag], lineBreak,
                            format ["BLUFOR: %1", west countSide allUnits], lineBreak,
                            format ["OPFOR: %1", east countSide allUnits], lineBreak,
                            format ["GUER: %1", resistance countSide allUnits], lineBreak,
                            format ["CIV: %1", civilian countSide allUnits], lineBreak,
                            format ["Dead: %1", count allDeadMen], lineBreak,
                            format ["Units in Real Time: %1", (count allUnits) - _cacheCountDiag], lineBreak,
                            format ["Units Cached: %1", _cacheCountDiag], lineBreak,
                            format ["Max Distance To Uncache: %1", maxDistanceScale]];
  };
  while {true} do { if (enableDiagPanel) then { ["clusterHC_EH_diagPanel", "onEachFrame", _panel] call BIS_fnc_addStackedEventHandler; sleep 1; ["clusterHC_EH_diagPanel", "onEachFrame"] call BIS_fnc_removeStackedEventHandler; } else {hintSilent ""; waitUntil {enableDiagPanel};}; };
};

_cacheUnits = {
  private ["_getGroupDistances", "_getFurthestElement", "_groupDistances", "_cacheCount", "_numUncached", "_numPlayers", "_furthestElement"];
  _getGroupDistances = getGroupDistances;
  _getFurthestElement = getFurthestElement;

  waitUntil {diag_fps <= fpsThreshold};  
  
  _cacheCount = 0;
  _groupDistances = call _getGroupDistances;
  waitUntil {!isNil "_groupDistances"};

  while {true} do {
    _numPlayers = 0;
    { if (isPlayer _x) then {_numPlayers = _numPlayers + 1;}; } forEach (allUnits);    
    waitUntil {diag_fps <= fpsThreshold};

    if ( _cacheCount == (((count _groupDistances) - 1) - _numPlayers) ) then {
      // Refresh cache
      _numUncached = 0;
      { if (simulationEnabled _x) then {_numUncached = _numUncached + 1;}; } forEach (allUnits);

      {
        if (diag_fps <= fpsThreshold) then {
          if (_numUncached < 150) then { if (!simulationEnabled _x) then {_x enableSimulation true; _numUncached = _numUncached + 1;}; };
        } else {
          {_x enableSimulation true;} forEach (allUnits);
        };
      } forEach ((position player) nearEntities maxDistanceScale);
      
      _cacheCount = 0;
      _groupDistances = call _getGroupDistances;
      waitUntil {!isNil "_groupDistances"};
    };

    _furthestElement = _groupDistances call _getFurthestElement;
    waitUntil {!isNil "_furthestElement"};

    if ( ((_groupDistances select _furthestElement) select 1) >= 0 ) then {
      {
        if (_x == (_groupDistances select _furthestElement) select 0) then {
          {
            if (!isPlayer _x) then {
              // If the AI unit has more than 5% health, then cache
              // Reasoning is that if an AI unit has <= 5% health, prevent caching them as they are dying for better immersion
              // Otherwise units can "freeze" as they die in awkward physics-defying positions, breaking immersion
              if ((damage _x) <= 0.95) then { if (simulationEnabled _x) then { _x enableSimulation false; }; };              
            };
          } forEach (units _x);
        };
      } forEach (allGroups);

      _groupDistances set [_furthestElement, [(allGroups select 0), -1]];
      _cacheCount = _cacheCount + 1;
    };
  };
};
///////////////////////// END PLAYER FUNCTIONS /////////////////////////

///////////////////////// START PLAYER ONLY CODE /////////////////////////
if (!isServer && hasInterface) exitWith {
  waitUntil {!isNull player};

  systemChat "Powered by clusterHC";

  [] spawn _simUnits;
  [] spawn _cacheUnits;
  [] spawn _diagPanel;
};
///////////////////////// END PLAYER ONLY CODE /////////////////////////

///////////////////////// START HC FUNCTIONS /////////////////////////
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
  private ["_getGroupDistances", "_getFurthestElement"];
  _getGroupDistances = getGroupDistances;
  _getFurthestElement = getFurthestElement;

  waitUntil {diag_fps <= fpsThreshold};
  while {true} do {
    waitUntil {diag_fps <= fpsThreshold};

    private ["_thisSimArray", "_numThisSimArray"];

    switch (profileName) do {
      case "HC": { _thisSimArray = HCSimArray; };
      case "HC2": { _thisSimArray = HC2SimArray; };
      case "HC3": { _thisSimArray = HC3SimArray; };
      default {diag_log "clusterHC: [ERROR] _cacheUnitsHC - Profile Name Not Recognized"; _thisSimArray = []; };
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
            if (_x == (_groupDistances select _furthestElement) select 0) then {
              {
                if (!isPlayer _x) then { if (simulationEnabled _x) then { _x enableSimulation false; }; };
              } forEach (units _x);

              _groupDistances set [_furthestElement, [(allGroups select 0), -1]];
            };
          } forEach (allGroups);
        };
      };
    };
  };
};
///////////////////////// END HC FUNCTIONS /////////////////////////

///////////////////////// START HC ONLY CODE /////////////////////////
if (!isServer && !hasInterface) exitWith {
  [] spawn _simUnits;
  [] spawn _cacheUnitsHC;
};
///////////////////////// END HC ONLY CODE /////////////////////////

///////////////////////// START SERVER FUNCTIONS /////////////////////////
_mpKilledEHCode = {
  [_this select 0] spawn {
    (_this select 0) enableSimulation true;
    sleep 3;
    (_this select 0) enableSimulation false;
    if (isServer) then {
      sleep corpseDecayTimer;
      deleteVehicle (_this select 0);
    };
  };
};
///////////////////////// END SERVER FUNCTIONS /////////////////////////

///////////////////////// START SERVER ONLY CODE /////////////////////////
_indexEHMPKilledArray = [ [(allUnits select 0), -1] ];
_indexEHLocalArray = [ [(allUnits select 0), -1] ];

while {true} do {
  { if (!isPlayer _x) then { _x enableSimulation false; }; } forEach (allUnits);

  // Rebalance every rebalanceTimer seconds to avoid hammering the server
  sleep rebalanceTimer;

  if (count _indexEHMPKilledArray > 1) then { { if (_forEachIndex > 0) then { (_x select 0) removeMPEventHandler ["MPKilled", (_x select 1)]; }; } forEach (_indexEHMPKilledArray); };
  if (count _indexEHLocalArray > 1) then { { if (_forEachIndex > 0) then { (_x select 0) removeMPEventHandler ["Local", (_x select 1)]; }; } forEach (_indexEHLocalArray); };
  
  _indexEHMPKilledArray = [ [(allUnits select 0), -1] ];
  _indexEHLocalArray = [ [(allUnits select 0), -1] ];
  {
    _indexMPKilled = _x addMPEventHandler ["MPKilled", _mpKilledEHCode];
    _indexEHMPKilledArray = _indexEHMPKilledArray + [[_x, _indexMPKilled]];
    _indexMPLocal = _x addMPEventHandler ["Local", { if (_this select 1) then {(_this select 0) enableSimulation true;} }];
    _indexEHLocalArray = _indexEHLocalArray + [[_x, _indexMPLocal]];
  } forEach (allUnits);

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

  // Determine first HC to start with
  _currentHC = 0;

  if (!isNull HC) then { _currentHC = 1; } else { 
    if (!isNull HC2) then { _currentHC = 2; } else { _currentHC = 3; };
  };

  // Balance the AI
  _numTransfered = 0;
  {
    _swap = true;

    // If a player is in this group, don't swap to an HC
    { if (isPlayer _x) then { _swap = false; }; } forEach (units _x);

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