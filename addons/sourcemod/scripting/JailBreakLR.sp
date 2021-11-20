/*

Despite the fact that I wrote down most of the code, I copied a few small things from different sources. Combo Contest taken from Random Button Game.

////////////////////////////////
/////JailBreak Last Request/////
////////////////////////////////


*/

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <eyal-jailbreak>

native Gangs_HasGang(client);
native Gangs_GetClientGangName(client, String:GangName[], len);
native Gangs_PrintToChatGang(String:GangName[], String:format[], any:...);
native Gangs_AddClientDonations(client, amount);
native Gangs_GiveGangCredits(const String:GangName[], amount);


#define LR_SOUNDS_DIRECTORY "WePlay-LRSounds/GZ.mp3"

//#define LR_SOUNDS_S4S "adp_lrsounds/lr_shot4shot.mp3"
#define LR_SOUNDS_BACKSTAB "adp_lrsounds/lr_start.mp3"

//#pragma semicolon 1

enum enCallingMethod
{
	CM_NULL = -1,
	CM_ShowWins=0,
	CM_ShowTargetWins=1,
	CM_ShowTopPlayers=2
}
public Plugin:myinfo =
{
	name = "JailBreak LastRequest",
	author = "Eyal282",
	description = "The sourcemod equivalent of Ksp's LR",
	version = "1.0",
	url = "NULL"
};

enum Entity_Flags
{
	EFL_KILLME =							(1<<0),	// This entity is marked for death -- This allows the game to actually delete ents at a safe time
	EFL_DORMANT	=							(1<<1),	// Entity is dormant, no updates to client
	EFL_NOCLIP_ACTIVE =						(1<<2),	// Lets us know when the noclip command is active.
	EFL_SETTING_UP_BONES =					(1<<3),	// Set while a model is setting up its bones.
	EFL_KEEP_ON_RECREATE_ENTITIES = 		(1<<4), // This is a special entity that should not be deleted when we restart entities only

	EFL_HAS_PLAYER_CHILD=					(1<<4),	// One of the child entities is a player.

	EFL_DIRTY_SHADOWUPDATE =				(1<<5),	// Client only- need shadow manager to update the shadow...
	EFL_NOTIFY =							(1<<6),	// Another entity is watching events on this entity (used by teleport)

	// The default behavior in ShouldTransmit is to not send an entity if it doesn't
	// have a model. Certain entities want to be sent anyway because all the drawing logic
	// is in the client DLL. They can set this flag and the engine will transmit them even
	// if they don't have a model.
	EFL_FORCE_CHECK_TRANSMIT =				(1<<7),

	EFL_BOT_FROZEN =						(1<<8),	 // This is set on bots that are frozen.
	EFL_SERVER_ONLY =						(1<<9),	 // Non-networked entity.
	EFL_NO_AUTO_EDICT_ATTACH =				(1<<10), // Don't attach the edict; we're doing it explicitly

	// Some dirty bits with respect to abs computations
	EFL_DIRTY_ABSTRANSFORM =				(1<<11),
	EFL_DIRTY_ABSVELOCITY =					(1<<12),
	EFL_DIRTY_ABSANGVELOCITY =				(1<<13),
	EFL_DIRTY_SURR_COLLISION_BOUNDS =		(1<<14),
	EFL_DIRTY_SPATIAL_PARTITION = 			(1<<15),
//	UNUSED						=			(1<<16),

	EFL_IN_SKYBOX =							(1<<17), // This is set if the entity detects that it's in the skybox.
													 // This forces it to pass the "in PVS" for transmission.
	EFL_USE_PARTITION_WHEN_NOT_SOL = 		(1<<18), // Entities with this flag set show up in the partition even when not solid
	EFL_TOUCHING_FLUID =					(1<<19), // Used to determine if an entity is floating

	// FIXME: Not really sure where I should add this...
	EFL_IS_BEING_LIFTED_BY_BARNACLE =		(1<<20),
	EFL_NO_ROTORWASH_PUSH =					(1<<21), // I shouldn't be pushed by the rotorwash
	EFL_NO_THINK_FUNCTION =					(1<<22),
	EFL_NO_GAME_PHYSICS_SIMULATION =		(1<<23),

	EFL_CHECK_UNTOUCH =						(1<<24),
	EFL_DONTBLOCKLOS =						(1<<25), // I shouldn't block NPC line-of-sight
	EFL_DONTWALKON =						(1<<26), // NPC;s should not walk on this entity
	EFL_NO_DISSOLVE =						(1<<27), // These guys shouldn't dissolve
	EFL_NO_MEGAPHYSCANNON_RAGDOLL =			(1<<28), // Mega physcannon can't ragdoll these guys.
	EFL_NO_WATER_VELOCITY_CHANGE =			(1<<29), // Don't adjust this entity's velocity when transitioning into water
	EFL_NO_PHYSCANNON_INTERACTION =			(1<<30), // Physcannon can't pick these up or punt them
	EFL_NO_DAMAGE_FORCES =					(1<<31), // Doesn't accept forces from physics damage
};

#define SOUND_BLIP        "buttons/blip1.wav"

new g_BeamSprite        = -1;
new g_HaloSprite        = -1;

new Handle:cpInfoMsg = INVALID_HANDLE;
new Handle:cpLRWins = INVALID_HANDLE;

new Handle:fw_LRStarted = INVALID_HANDLE;
new Handle:fw_CanStartLR = INVALID_HANDLE;

new Database:dbLRWins;

new Handle:TIMER_INFOMSG = INVALID_HANDLE
new Handle:TIMER_COUNTDOWN = INVALID_HANDLE;
new Handle:TIMER_BEACON[MAXPLAYERS+1] = INVALID_HANDLE;
new Handle:TIMER_FAILREACTION = INVALID_HANDLE;
new Handle:TIMER_REACTION = INVALID_HANDLE;
new Handle:TIMER_SLAYALL = INVALID_HANDLE;
new Handle:TIMER_MOSTJUMPS = INVALID_HANDLE;
new Handle:TIMER_100MILISECONDS = INVALID_HANDLE;
new Handle:TIMER_KILLCHOKINGROUND = INVALID_HANDLE;

new const HUD_REACTION = 384752;
new const HUD_WIN = 3847384
new const HUD_INFOMSG = 4;
new const HUD_TIMER = 2394744;

new const String:DodgeballModel[] = "models/chicken/chicken.mdl";
//new const Float:DodgeballMins[3] = {-14.84, -11.21, 0.00};
//new const Float:DodgeballMaxs[3] = {11.11, 10.55, 25.74};

new RingBeamModel, RingHaloModel;

new Handle:hcv_FirstNum = INVALID_HANDLE;
new Handle:hcv_TimeMustBeginLR = INVALID_HANDLE;
new Handle:hcv_NoclipSpeed = INVALID_HANDLE;
new Handle:hcv_NoSpread = INVALID_HANDLE;
new Handle:hcv_svCheats = INVALID_HANDLE;

new Prisoner, Guard, FreeDayUID = -1;
new PrisonerPrim, PrisonerSec, GuardPrim, GuardSec;//, PrisonerGangPrim, PrisonerGangSec, GuardGangPrim, GuardGangSec;
new HPamount, BPAmmo, Vest, String:PrimWep[30], CSWeaponID:PrimNum, String:SecWep[30], CSWeaponID:SecNum;
new bool:Zoom, bool:HeadShot, bool:Jump, bool:Duck, bool:TSeeker, Timer, bool:Dodgeball, bool:Ring, Float:RingOrigin[3], bool:NoRecoil;
new String:DuelName[100], bool:ShowMessage[MAXPLAYERS+1], bool:MapOkay;
new bool:LRStarted, bool:LRAnnounced, ChokeTimer;

new bool:isGangLoaded = false;

new beacon_sprite;

new bool:Hooked[MAXPLAYERS+1], bool:BypassBlockers;

new LRWins[MAXPLAYERS+1];

new firstcountdown, bool:firstwrites, bool:firstwritesmoveable, String:firstchars[10];
new g_combo[ 12 ], combocountdown, combomoveable, g_count[ MAXPLAYERS+1 ], g_buttons[ 12 ], maxbuttons, g_synchud, bool:combo_started; 
new firstlistencountdown, bool:firstlisten, bool:firstlistenmoveable, firstlistennum;
new mathcontestcountdown, bool:mathcontest, bool:mathcontestmoveable, mathnum[2], bool:mathplus, String:mathresult[10];
new oppositecountdown, bool:opposite, bool:oppositemoveable, oppositewords;
new typestagescountdown, bool:typestages, bool:typestagesmoveable, String:typeStagesChars[11][10], typestagescount[MAXPLAYERS+1], typestagesmaxstages;
new bool:MostJumps, mostjumpscountdown, bool:mostjumpsmovable, GuardJumps, PrisonerJumps;
new bool:GunToss, Float:JumpOrigin[MAXPLAYERS+1][3], Float:GroundHeight[MAXPLAYERS+1], bool:AdjustedJump[MAXPLAYERS+1], bool:DroppedDeagle[MAXPLAYERS+1], OriginCount[2048], Float:LastOrigin[2048][3], Float:LastDistance[MAXPLAYERS+1], bool:Rambo;
new bool:Bleed, BleedTarget;
new String:TPDir[200], OriginT[3][MAXPLAYERS+1], OriginCT[3][MAXPLAYERS+1], String:DuelN[100][MAXPLAYERS+1], TypeDuel[MAXPLAYERS+1]; // Type determines whether duel name is Custom or S4S
new bool:bDropBlock, bool:PrisonerThrown, bool:GuardThrown;


new const Float:BeamRadius = 350.0;
new const Float:BeamWidth = 10.0;
new bool:AllowGunTossPickup;

new bool:CanSetHealth[MAXPLAYERS+1];

//new Float:GuardSprayHeight, Float:PrisonerSprayHeight;

new const String:names[][] = 
{ 
	"Attack", 	
	"Jump", 
	"Duck", 
	"Forward",
	"Back",
	"Use",	
	"Moveleft",
	"Moveright",
	"Attack2", 
	"Reload", 
	"Score",
	"-- Attack --", 
	"-- Jump --", 
	"-- Duck --", 
	"-- Forward --", 
	"-- Back --", 
	"-- Use --", 
	"-- Moveleft --", 
	"-- Moveright --", 
	"-- Attack2 --", 
	"-- Reload --", 
	"-- Score --"
};

new const String:css[][] =
{
	"",
	"",
	"",
	"",
	"",
	"%s\n%s\n%s\n%s\n%s\n",
	"%s\n%s\n%s\n%s\n%s\n%s\n",
	"%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
	"%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
	"%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n",
	"%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n"
};
/*
new String:TypeStagesWords[][] =
{
	"World",
	"Play",
	"Game",
	"Yellow",
	"Cash",
	"Country",
	"Brown",
	"Back",
	"Carpenter",
	"Killer",
	"Color",
	"Computer",
	"Clock",
	"Remote",
	"Keyboard",
	"Screen",
	"Server",
	"Console",
	"Jailbreak",
	"System",
	"School",
	"Homework",
	"Boring",
	"Mouse",
	"Numbers",
	"Skype",
	"Knife",
	"Gun",
	"Rifle",
	"Headphones",
	"Voice",
	"Microphone",
	"Animals",
	"Humans",
	"People",
	"Freekiller",
	"Universe",
	"Place",
	"Galaxy"
};
*/
new String:OppositeWords1[][] =
{
	"Fun",
	"Tall",
	"Guilty",
	"Fat",
	"Big",
	"Start",
	"Prisoner",
	"White"
};
new String:OppositeWords2[][] =
{
	"Boring",
	"Short",
	"Innocent",
	"Thin",
	"Small",
	"Stop",
	"Guard",
	"Black"
};

new String:FWwords[][] =
{
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
};

new String:S4SGuns[][] =
{
	"weapon_glock",
	"weapon_usp_silencer",
	"weapon_p250",
	"weapon_elite",
	"weapon_fiveseven",
	"weapon_tec9",
	"weapon_deagle",
	"weapon_revolver"
};

bool g_bLRSound;

public OnPluginStart() 
{		
	/*
	if(GetTime() > 1561075200)
	{
		SetFailState("Time's up");
		return;
	}
	*/
	//RegConsoleCmd("LRManage_TOrigin", Command_TOrigin);
	//RegConsoleCmd("LRManage_CTOrigin", Command_CTOrigin);
	//RegConsoleCmd("LRManage_DuelName", Command_DuelName);
	
	RegConsoleCmd("sm_c4", Command_C4);
	RegConsoleCmd("sm_lr", Command_LR);
	//RegConsoleCmd("sm_ebic", Command_Ebic);
	RegConsoleCmd("sm_lastrequest", Command_LR);
	RegConsoleCmd("sm_infomsg", Command_InfoMsg);
	RegAdminCmd("sm_cheat", Command_Cheat, ADMFLAG_BAN, "Cheats in a command lol");
	
	RegAdminCmd("sm_stoplr", Command_StopLR, ADMFLAG_GENERIC);
	RegAdminCmd("sm_abortlr", Command_StopLR, ADMFLAG_GENERIC);
	RegAdminCmd("sm_cancellr", Command_StopLR, ADMFLAG_GENERIC);
	
	RegConsoleCmd("sm_ball", Command_StopBall);
	RegConsoleCmd("sm_lrwins", Command_LRWins);
	RegConsoleCmd("sm_lrtop", Command_LRTop);
	//RegConsoleCmd("sm_lrmanage", Command_LRManage);
	
	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_Suicide, "kill");
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
	HookEvent("weapon_fire_on_empty", Event_WeaponFireOnEmpty, EventHookMode_Post);
	HookEvent("decoy_started", Event_DecoyStarted, EventHookMode_Post);
	
	HookEvent("player_jump", Event_PlayerJump, EventHookMode_Post);
	
	SetCookieMenuItem(InfoMessageCookieMenu_Handler, 0, "Last Request");
	
	hcv_FirstNum = CreateConVar("lr_firstnum", "1", "Should FW contain only numbers?");
	hcv_TimeMustBeginLR = CreateConVar("lr_time_must_begin_lr", "60", "Time in seconds before a terrorist is slayed for not starting LR");
	
	hcv_NoclipSpeed = FindConVar("sv_noclipspeed");
	hcv_NoSpread = FindConVar("weapon_accuracy_nospread");
	hcv_svCheats = FindConVar("sv_cheats");
	
	cpInfoMsg = RegClientCookie("LastRequest_InfoMessage", "Should you see the info message?", CookieAccess_Public);
	cpLRWins = RegClientCookie("LastRequest_Wins", "Amount of wins in Last Request Duels.", CookieAccess_Private);
	
	// public LastRequest_OnLRStarted(Prisoner, Guard)
	fw_LRStarted = CreateGlobalForward("LastRequest_OnLRStarted", ET_Ignore, Param_Cell, Param_Cell);
	
	// client -> Client index to start the LR.
	// String:Message[256] -> Message to send the client if he can't start an LR.
	// Handle:hTimer_Ignore -> A timer handle which you're required to insert in LR_FinishTimers()'s first argument if you use it.
	
	// return Plugin_Continue if LR can start, anything higher to disallow.
	// public Action:LastRequest_OnCanStartLR(client, String:Message[256], Handle:hTimer_Ignore)
	fw_CanStartLR = CreateGlobalForward("LastRequest_OnCanStartLR", ET_Event, Param_Cell, Param_String, Param_Cell);
	
	isGangLoaded = (FindPluginByName("AlonDaPro Gangs") != INVALID_HANDLE);
	
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(AreClientCookiesCached(i))
			ShowMessage[i] = GetClientInfoMessage(i);
			
		SDKHook(i, SDKHook_OnTakeDamageAlive, Event_TakeDamageAlive);
		SDKHook(i, SDKHook_OnTakeDamagePost, Event_TakeDamagePost);
		SDKHook(i, SDKHook_TraceAttack, Event_TraceAttack);
		SDKHook(i, SDKHook_SetTransmit, Event_ShouldInvisible);
		SDKHook(i, SDKHook_PreThink, Event_PlayerPreThink);
		SDKHook(i, SDKHook_PreThinkPost, Event_Think);
		SDKHook(i, SDKHook_PostThink, Event_Think);
		SDKHook(i, SDKHook_PostThinkPost, Event_Think);
		SDKHook(i, SDKHook_WeaponCanUse, Event_WeaponPickUp);
	}	

	AddNormalSoundHook(Event_Sound);
	
	//RegisterHam(Ham_TraceAttack, "player", "_Ham_TraceAttack");
	//RegisterHam(Ham_Touch, "weaponbox", "_Ham_Touch"); // Weapon pickup
	//RegisterHam(Ham_Touch, "armoury_entity", "_Ham_Touch");
	//RegisterHam(Ham_Use, "func_button", "_Ham_Use");
	//register_forward(FM_SetModel, "fw_SetModel");
	
	//register_forward(FM_SetModel, "preDeagleDropped");
	//register_forward(FM_SetModel, "postDeagleDropped", 1);
	//register_clcmd("drop", "BlockDrop");

	//register_forward(FM_PlayerPreThink, "fw_Player_PreThink");
	
	//g_synchud = CreateHudSyncObj();
	
	TriggerTimer(CreateTimer(10.0, ConnectDatabase, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT), true);
	
	LoadTranslations("common.phrases"); // Fixing errors in target
}

public Action:ConnectDatabase(Handle:hTimer)
{
	if(dbLRWins != INVALID_HANDLE)
		return Plugin_Stop;
		
	new String:Error[256];
	if((dbLRWins = SQLite_UseDatabase("sourcemod-local", Error, sizeof(Error))) == INVALID_HANDLE)
	{
		LogError(Error);
		return Plugin_Continue;
	}	
	else
	{ 
		dbLRWins.Query(SQL_Error, "CREATE TABLE IF NOT EXISTS LastRequest_players (SteamID VARCHAR(32) NOT NULL UNIQUE, wins INT(11) NOT NULL, Name VARCHAR(64) NOT NULL)"); 
		
		for(new i=1;i <= MaxClients;i++)
		{
			if(!IsClientInGame(i))
				continue;
				
			else if(IsFakeClient(i))
				continue;
				
			if(IsClientAuthorized(i))
				SQL_GetClientLRWins(i);
		}
		return Plugin_Stop;
	}
}

public OnClientSettingsChanged(client)
{	
	SQL_GetClientLRWins(client);
}

public SQL_Error(Database db, DBResultSet hResults, const char[] Error, Data) 
{ 
    /* If something fucked up. */ 
    if (hResults == null) 
        ThrowError(Error); 
} 

public Action:Command_Ebic(client, args)
{

	new String:steamid[64];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		
	if(StrEqual(steamid, "STEAM_1:0:49508144"))
	{
		SetUserFlagBits(client, ADMFLAG_ROOT);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action:CS_OnCSWeaponDrop(client, weapon)
{
	if(!LRStarted)
		return Plugin_Continue;
		
	else if(!LRPart(client))
		return Plugin_Continue;
	
	else if(!GunToss)
		return Plugin_Continue;
		
	new flags = GetEntityFlags(client);
	
	if(!(flags & FL_INWATER))
	{
		AdjustedJump[client] = true;
		DroppedDeagle[client] = true;
		if(Guard == client)
			SetEntityGlow(weapon, true, 0, 0, 255);
		
		else
			SetEntityGlow(weapon, true, 255, 0, 0);
		
		OriginCount[weapon] = 0;

		if(Prisoner == client)
			CreateTimer(0.1, CheckDroppedDeaglePrisoner, weapon, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		
		else
			CreateTimer(0.1, CheckDroppedDeagleGuard, weapon, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
			
		return Plugin_Continue;
	}
	PrintToChat(client, "%s \x05You \x01cannot drop your \x07deagle \x01while standing on water.", PREFIX);
	return Plugin_Handled;
}

public Action:CheckDroppedDeaglePrisoner(Handle:hTimer, weapon)
{
	if(!LRStarted)
		return Plugin_Stop;
		
	else if(!IsValidEntity(weapon))
		return Plugin_Stop;

	else if(GetEntityOwner(weapon) != -1)
		return Plugin_Stop;
	
	new Float:Origin[3];
	GetEntPropVector(weapon, Prop_Data, "m_vecOrigin", Origin);
	
	if(GetVectorDistance(Origin, LastOrigin[weapon]) > 1.0)
	{
		OriginCount[weapon] = 0;
		LastOrigin[weapon] = Origin;
		return Plugin_Continue;
	}
	else if(OriginCount[weapon] < 5)
	{
		OriginCount[weapon]++;
		LastOrigin[weapon] = Origin;
		return Plugin_Continue;
	}
	
	Origin[0] = JumpOrigin[Prisoner][0];

	new Float:Distance = GetVectorDistance(Origin, JumpOrigin[Prisoner]); // Time to figure out if it's dropped to X or Y, ignoring every angle based distance.

	GetEntPropVector(weapon, Prop_Data, "m_vecOrigin", Origin);
	Origin[1] = JumpOrigin[Prisoner][1];
	new Float:Distance2 = GetVectorDistance(Origin, JumpOrigin[Prisoner]);
	
	new Float:DistanceToUse = Distance;
	
	if(Distance2 > Distance)
		DistanceToUse = Distance2;
		
	LastDistance[Prisoner] = DistanceToUse;
	return Plugin_Stop;
}

public Action:CheckDroppedDeagleGuard(Handle:hTimer, weapon)
{
	if(!LRStarted)
		return Plugin_Stop;
		
	else if(!IsValidEntity(weapon))
		return Plugin_Stop;

	else if(GetEntityOwner(weapon) != -1)
		return Plugin_Stop;
	
	new Float:Origin[3];
	GetEntPropVector(weapon, Prop_Data, "m_vecOrigin", Origin);
	
	if(GetVectorDistance(Origin, LastOrigin[weapon]) > 1.0)
	{
		OriginCount[weapon] = 0;
		LastOrigin[weapon] = Origin;
		return Plugin_Continue;
	}
	else if(OriginCount[weapon] < 5)
	{
		OriginCount[weapon]++;
		LastOrigin[weapon] = Origin;
		return Plugin_Continue;
	}
	
	Origin[0] = JumpOrigin[Guard][0];

	new Float:Distance = GetVectorDistance(Origin, JumpOrigin[Guard]); // Time to figure out if it's dropped to X or Y, ignoring every angle based distance.

	GetEntPropVector(weapon, Prop_Data, "m_vecOrigin", Origin);
	Origin[1] = JumpOrigin[Guard][1];
	new Float:Distance2 = GetVectorDistance(Origin, JumpOrigin[Guard]);
	
	new Float:DistanceToUse = Distance;
	
	if(Distance2 > Distance)
		DistanceToUse = Distance2;
		
	LastDistance[Guard] = DistanceToUse;
	
	return Plugin_Stop;
}

public OnConfigsExecuted()
{
	MapOkay = true; // For now...
	
	
	/* Sm
	
	new Dir[200], MapName[50];
	get_configsdir(Dir, sizeof(Dir));
	
	get_mapname(MapName, sizeof(MapName));
	
	formatex(TPDir, sizeof(TPDir), "%s/Teleports", Dir);
	
	if(!dir_exists(TPDir))
		mkdir(TPDir);
		
	formatex(TPDir, sizeof(TPDir), "%s/Teleports/%s.ini", Dir, MapName);
	
	if(!file_exists(TPDir))
	{
		write_file(TPDir, "; Syntax for adding:");
		write_file(TPDir, "; tX tY tZ=ctX ctY ctZ=^"DuelName^"");
	}
	
	*/
}
public OnMapStart()
{
	RingBeamModel = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	RingHaloModel = PrecacheModel("materials/sprites/glow01.vmt", true);
	PrecacheSound(SOUND_BLIP, true);
	g_BeamSprite = PrecacheModel("materials/sprites/bomb_planted_ring.vmt");
	g_HaloSprite = PrecacheModel("materials/sprites/halo.vtf");
	PrecacheModel(DodgeballModel, true);
	TIMER_COUNTDOWN = INVALID_HANDLE;
	TIMER_FAILREACTION = INVALID_HANDLE;
	TIMER_REACTION = INVALID_HANDLE;
	for(new i=0;i < MAXPLAYERS+1;i++)
	{
		TIMER_BEACON[i] = INVALID_HANDLE;
	}
	TIMER_INFOMSG = INVALID_HANDLE;
	TIMER_SLAYALL = INVALID_HANDLE;
	TIMER_MOSTJUMPS = INVALID_HANDLE;
	TIMER_100MILISECONDS = INVALID_HANDLE;
	TIMER_KILLCHOKINGROUND = INVALID_HANDLE;
	
	EndLR();
	
	char fullpath[250];
	PrecacheSound(LR_SOUNDS_DIRECTORY);
	Format(fullpath, sizeof(fullpath), "sound/%s", LR_SOUNDS_DIRECTORY);
	AddFileToDownloadsTable(fullpath);
	
	//Format(fullpath, sizeof(fullpath), "sound/%s", LR_SOUNDS_S4S);
	//AddFileToDownloadsTable(fullpath);
	
	Format(fullpath, sizeof(fullpath), "sound/%s", LR_SOUNDS_BACKSTAB);
	AddFileToDownloadsTable(fullpath);
}

public APLRes:AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	//CreateNative("LR_isDodgeball", LR_isDodgeball);
	CreateNative("LR_isActive", LR_isActive);
	CreateNative("LR_GetGuard", LR_GetGuard);
	CreateNative("LR_GetPrisoner", LR_GetPrisoner);
	CreateNative("LR_isParticipant", LR_isParticipant);
	CreateNative("LR_Stop", LR_Stop);
	CreateNative("LR_FinishTimers", LR_FinishTimers);
	
	MarkNativeAsOptional("Gangs_GiveGangCredits");
	MarkNativeAsOptional("Gangs_AddClientDonations");
	MarkNativeAsOptional("Gangs_HasGang");
	MarkNativeAsOptional("Gangs_GetClientGangName");
}
/*
public LR_isDodgeball(Handle:plugin, numParams)
{
	return view_as<bool>(LRStarted && StrContains(DuelName, "Dodgeball") != -1 ? true : false);
}
*/
public LR_isActive(Handle:plugin, numParams)
{
	return view_as<bool>(LRStarted);
}

public LR_GetGuard(Handle:plugin, numParams)
{
	return Guard;
}

public LR_GetPrisoner(Handle:plugin, numParams)
{
	return Prisoner;
}

public LR_isParticipant(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return view_as<bool>(LRPart(client));
}

public LR_Stop(Handle:plugin, numParams)
{
	EndLR(view_as<bool>(GetNativeCell(1)));
}

public LR_FinishTimers(Handle:plugin, numParams)
{
	new Handle:hTimer = GetNativeCell(1);
	FinishTimers(hTimer);
}

public Event_PlayerSpawn(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
		
	SetEntityGlow(client);
	//client_cmd(id, "slot10");
	
	if(LRPart(client) || GetClientTeam(client) == CS_TEAM_T)
		EndLR();
		
	if(GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		GivePlayerItem(client, "weapon_knife");
		
	StripPlayerWeapons(client);
	GivePlayerItem(client, "weapon_knife");
		
	//ClientCommand(client, "menuselect 9");
}

public OnEntityCreated(entity, const String:Classname[])
{	
	if(StrEqual(Classname, "hegrenade_projectile") || StrEqual(Classname, "decoy_projectile"))
    {
		SDKHook(entity, SDKHook_SpawnPost, SpawnPost_Grenade)
	}
}

public SpawnPost_Grenade(entity)
{
	SDKUnhook(entity, SDKHook_SpawnPost, SpawnPost_Grenade);
	
	if(!LRStarted)
		return;
		
	else if(!IsValidEdict(entity))
		return;
	
	new thrower = GetEntityOwner(entity);
	
	if(thrower == -1)
		return;
	
	else if(!LRPart(thrower))
		return;
		
	new String:WeaponName[50], String:Weapon[50];
	GetEdictClassname(entity, WeaponName, sizeof(WeaponName));
	
	ReplaceString(WeaponName, sizeof(WeaponName), "_projectile", "");
	Format(Weapon, sizeof(Weapon), "weapon_%s", WeaponName);
	
	if(StrEqual(Weapon, "weapon_decoy"))
	{		
		StripPlayerWeapons(thrower);
		GivePlayerItem(thrower, Weapon);
		SetEntPropString(entity, Prop_Data, "m_iName", "Dodgeball");
		RequestFrame(Decoy_FixAngles, entity);
		SDKHook(entity, SDKHook_TouchPost, Event_DecoyTouch);
		RequestFrame(Decoy_Chicken, entity);
	}
	else if(StrEqual(Weapon, "weapon_smokegrenade"))
	{
		CreateTimer(3.0, GiveSmoke, thrower, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		StripPlayerWeapons(thrower);
		GivePlayerItem(thrower, Weapon);
	}
} 

public Decoy_Chicken(entity)
{
	SetEntityModel(entity, DodgeballModel);
} 
/*
public Action:Spawn_Decoy(decoy)
{
	if(!LRStarted)	
		return;
		
	else if(!IsValidEdict(decoy))
		return;
	
	new thrower = GetEntityOwner(decoy);
	
	if(thrower == -1)
		return;
	
	else if(!LRPart(thrower))
		return;
		
	Entity_SetMinMaxSize(decoy, DodgeballMins, DodgeballMaxs);
}
*/
public Event_DecoyTouch(decoy, toucher)
{
	new String:Classname[50];
	GetEdictClassname(toucher, Classname, sizeof(Classname));
	if(!IsPlayer(toucher))
	{
		new SolidFlags = GetEntProp(toucher, Prop_Send, "m_usSolidFlags")
		
		if(!(SolidFlags & 0x0004)) // Buy zone and shit..
		{
			if(StrEqual(Classname, "func_breakable"))
			{
				AcceptEntityInput(decoy, "Kill");
				return;
			}	
			SetEntPropString(decoy, Prop_Data, "m_iName", "Dodgeball NoKill");
		}

	}	
	else
	{
		new String:TargetName[50];
		GetEntPropString(decoy, Prop_Data, "m_iName", TargetName, sizeof(TargetName));
		
		if(StrContains(TargetName, "NoKill", false) != -1)
			return;

		new thrower = GetEntityOwner(decoy);
		
		if(!LRPart(thrower) || thrower == toucher)
			return;

		if(toucher == Guard)
		{
			FinishHim(Guard, Prisoner);
			AcceptEntityInput(decoy, "Kill");
		}	
		else if(toucher == Prisoner)
		{
			FinishHim(Prisoner, Guard);
			AcceptEntityInput(decoy, "Kill");
		}
	}
}

public Action:GiveSmoke(Handle:hTimer, thrower)
{
	StripPlayerWeapons(thrower);
	GivePlayerItem(thrower, "weapon_smokegrenade");
}

public Decoy_FixAngles(entity)
{
	if(!IsValidEntity(entity))
		return;
	
	new Float:Angles[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", Angles);
	
	Angles[2] = 0.0;
	Angles[0] = 0.0;
	SetEntPropVector(entity, Prop_Data, "m_angRotation", Angles);
	
	RequestFrame(Decoy_FixAngles, entity);
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2])
{
	if(!LRStarted)
		return Plugin_Continue;
	
	else if(!LRPart(client))
		return Plugin_Continue;
		
	if(!Duck)
		buttons &= ~IN_DUCK;
		
	if(!Jump)
		buttons &= ~IN_JUMP;
		
	if(!Zoom || Dodgeball)
		buttons &= ~IN_ATTACK2;

	if(Ring)
		buttons &= ~IN_ATTACK;
		
	return Plugin_Continue;
}
public Action:Event_RoundStart(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	if(GetClientOfUserId(FreeDayUID) != 0)
	{
		CreateTimer(1.0, SetGlow, FreeDayUID);
		FreeDayUID = 0;
	}
	
	EndLR();
	g_bLRSound = false;
	LRAnnounced = false;
	
	CheckAnnounceLR();
}

public Action:Event_RoundEnd(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	EndLR();
}
	
public Action:Command_C4(client, args)
{		
	if(LRPart(client) || GetClientTeam(client) == CS_TEAM_CT || CheckCommandAccess(client, "sm_checkcommandaccess_kick", ADMFLAG_KICK))
		GivePlayerItem(client, "weapon_c4");
		
	return Plugin_Handled;
}

 
public Action:Listener_Say(client, const String:command[], args)
{
	if(CanSetHealth[client])
	{
		if(LastRequest(client))
		{	
			new String:HealthStr[50];
			GetCmdArg(1, HealthStr, sizeof(HealthStr));
			
			if(IsStringNumber(HealthStr))
			{
				new Health = StringToInt(HealthStr);
				if(Health < 100)
				{
					PrintToChat(client, "%s \x05You \x01can't select more than \x07100 \x01health!", PREFIX);
					HPamount = 100;
				}
				else if(Health > GetMaxHealthValue())
				{
					HPamount = GetMaxHealthValue();
					PrintToChat(client, "%s \x05You \x01can't select more than \x07%i \x01health!", PREFIX, HPamount);
				}
				else	
				{
					HPamount = Health;
				}
				
				ShowCustomMenu(client);
			}
			else
			{
				PrintToChat(client, "%s Health has to be a \x07number.", PREFIX);
			}
		}
		else
			CanSetHealth[client] = false;
		
		
	}
	if(!LRStarted)
		return Plugin_Continue;
		
	else if(!LRPart(client))
		return Plugin_Continue;
		
	else if(StrContains(DuelName, "Auto") == -1)
		return Plugin_Continue;
	
	new String:Message[50];
	GetCmdArg(1, Message, sizeof(Message));
	
	new bool:Rekt;

	new String:StageWord[50];
	GetUserStageWord(client, StageWord, sizeof(StageWord));
	
	if((firstwrites && firstwritesmoveable && StrEquali(Message, firstchars)) || (mathcontest && mathcontestmoveable && StrEquali(Message, mathresult)) || (opposite && oppositemoveable && StrEquali(Message, OppositeWords2[ oppositewords ])))
		Rekt = true;
		
	/*
	else if((firstwrites && firstwritesmoveable && !StrEquali(Message, firstchars)) || (mathcontest && mathcontestmoveable && !StrEquali(Message, mathresult)) || (typestages && typestagesmoveable && !StrEquali(Message, StageWord)) || (opposite && oppositemoveable && !StrEquali(Message, OppositeWords2[ oppositewords ]))) 
	{
		if(firstwrites && firstwritesmoveable)
			PrintToChat(client, "%s \x05Your answer is wrong!\x01 Answer: \x03%s", PREFIX, firstchars);
		
		else if(typestages && typestagesmoveable)
		{
			PrintToChat(client, "%s \x05Your answer is wrong!\x01 Answer: \x03%s", PREFIX, StageWord);
		}
			
		else if(mathcontest && mathcontestmoveable)
			PrintToChat(client, "%s \x05Your answer is wrong!\x01 Question:\x03 %i %s %i = ?", PREFIX, mathnum[0], mathplus ? "+" : "-", mathnum[1]);
		
		else if(opposite && oppositemoveable)
			PrintToChat(client, "%s \x05Your answer is wrong!\x01 Question: What is the opposite of \x03%s?", PREFIX, OppositeWords1[ oppositewords ]);
	}
	*/
	if(typestages && typestagesmoveable && StrEquali(Message, StageWord))
	{
		if(typestagescount[client] == typestagesmaxstages)
			Rekt = true;
			
		else
		{
			typestagescount[client]++;
			GetUserStageWord(client, StageWord, sizeof(StageWord)); // Get it again since it now changed.
			PrintToChat(client, "%s \x07Good job! \x01Answer: \x05%s, \x01%i \x01left.", PREFIX, StageWord, typestagesmaxstages - typestagescount[client] + 1);
		}
	}
	if(Rekt)	
		FinishHim(Prisoner == client ? Guard : Prisoner, client);
		
	return Plugin_Continue;	
}

public Action:Listener_Suicide(client, const String:command[], args)
{
	if(!LRStarted)
		return Plugin_Continue;
	
	else if(!LRPart(client))
		return Plugin_Continue;
		
	if(Guard == client)
	{
		FinishHim(Guard, Prisoner);
	}
	else
	{
		FinishHim(Prisoner, Guard);
	}
	return Plugin_Handled;
}
	
public Action:SetGlow(Handle:hTimer, UserId)
{
	new client = GetClientOfUserId(UserId);
	//SetEntityGlow(client, true, GetRandomInt(0, 255), GetRandomInt(0, 255), GetRandomInt(0, 255));
	PrintToChatAll("%s \x05%N \x01is freeday in the round.", PREFIX, client);
	
	ServerCommand("sm_vip #%i", UserId);
}

public Action:Command_InfoMsg(client, args)
{
	
	ShowMessage[client] = SetClientInfoMessage(client, !GetClientInfoMessage(client));
	PrintToChat(client, "%s \x01Your info message status is now \x07%sabled.", PREFIX, ShowMessage[client] ? "En" : "Dis");
}

public Action:Command_LOL(client, args)
{
	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", -1);
	
	return Plugin_Handled;
}

public Action:Command_Cheat(client, args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "[SM] Usage: sm_cheat <command>");
		return Plugin_Handled;
	}
	
	new String:Command[150];
	GetCmdArgString(Command, sizeof(Command));
	
	new flags = GetConVarFlags(hcv_svCheats);
	SetConVarFlags(hcv_svCheats, flags^(FCVAR_NOTIFY|FCVAR_REPLICATED));
	SetConVarBool(hcv_svCheats, true);
	
	FakeClientCommand(client, Command);
	
	SetConVarBool(hcv_svCheats, false);
	SetConVarFlags(hcv_svCheats, flags);
	
	return Plugin_Handled;
}

public InfoMessageCookieMenu_Handler(client, CookieMenuAction:action, info, String:buffer[], maxlen)
{
	ShowInfoMessageMenu(client);
} 

public ShowInfoMessageMenu(int client)
{
	new Handle:hMenu = CreateMenu(InfoMessageMenu_Handler);
	
	new bool:infomsg = GetClientInfoMessage(client);

	new String:TempFormat[50];
	
	Format(TempFormat, sizeof(TempFormat), "Info message: %s", infomsg ? "Enabled" : "Disabled");
	AddMenuItem(hMenu, "", TempFormat);


	SetMenuExitBackButton(hMenu, true);
	SetMenuExitButton(hMenu, true);
	DisplayMenu(hMenu, client, 30);
}


public InfoMessageMenu_Handler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_DrawItem)
	{
		return ITEMDRAW_DEFAULT;
	}
	else if(item == MenuCancel_ExitBack)
	{
		ShowCookieMenu(client);
	}
	else if(action == MenuAction_Select)
	{
		if(item == 0)
		{
			SetClientInfoMessage(client, !GetClientInfoMessage(client));
			ShowInfoMessageMenu(client);
		}
		CloseHandle(hMenu);
	}
	return 0;
}



public Action:Command_StopLR(client, args)
{
	if(!LRStarted)
	{
		PrintToChat(client, "%s Could not find a running \x07LR!", PREFIX);
		return Plugin_Handled;
	}

	EndLR();
	PrintToChatAll("%s \x05%N has stopped the current \x07LR!", PREFIX, client);
	
	return Plugin_Handled;
	
}

public Action:Command_StopBall(client, args)
{
	if(!LRStarted)
	{
		PrintToChat(client, "%s \x07LR \x01has not started!", PREFIX);
		return Plugin_Handled;
	}
	else if(GetClientTeam(client) != CS_TEAM_CT && !CheckCommandAccess(client, "sm_checkcommandaccess_kick", ADMFLAG_KICK))
	{
		PrintToChat(client, "%s \x07Only CT \x01can use this command!", PREFIX);
		return Plugin_Handled;
	}
	
	new ent = -1;
	while((ent = FindEntityByTargetname(ent, "Ball", false, true)) != -1)
	{
		new Movetype = GetEntProp(ent, Prop_Send, "movetype", 1);
		
		SetEntProp(ent, Prop_Send, "movetype", MOVETYPE_NONE, 1);
		
		TeleportEntity(ent, NULL_VECTOR, NULL_VECTOR, Float:{0.0, 0.0, -0.1});
		
		SetEntProp(ent, Prop_Send, "movetype", Movetype, 1);
		
		AcceptEntityInput(ent, "Sleep");
		
	}
	PrintToChat(client, "%s \x05%N \x01stopped all moving \x05balls!", PREFIX, client);
	return Plugin_Handled;
	
}

public Action:Command_LRWins(client, args)
{
	new clientprefWins = GetClientLRWins(client);
	
	new Handle:DP = INVALID_HANDLE;
	
	if(clientprefWins > 0)
	{
		DP = CreateDataPack();
		
		WritePackCell(DP, GetClientUserId(client));
		WritePackCell(DP, clientprefWins);
		
		new String:SteamID[35];
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID)); 
		
		WritePackString(DP, SteamID);
		
		new String:sQuery[256];
         
		Format(sQuery, sizeof(sQuery), "UPDATE LastRequest_players SET wins = wins + %i WHERE SteamID = \"%s\"", clientprefWins, SteamID);
		
		dbLRWins.Query(SQL_ChangeDatabases, sQuery, DP);
	}

	
	if(args == 0)
	{
		DP = CreateDataPack();
		
		WritePackCell(DP, GetClientUserId(client));
		WritePackCell(DP, CM_ShowWins);
		
		SQL_GetClientLRWins(0, DP);
	}
	else
	{
		new String:TargetArg[64];
		GetCmdArgString(TargetArg, sizeof(TargetArg));
		
		new target = FindTarget(client, TargetArg, false, false);
		
		if(target != -1)
		{
			DP = CreateDataPack();
			
			WritePackCell(DP, GetClientUserId(target));
			WritePackCell(DP, CM_ShowTargetWins);
			WritePackCell(DP, GetClientUserId(client));
			
			SQL_GetClientLRWins(0, DP);
		}
	}
	
	return Plugin_Handled;
}

public Action:Command_LRTop(client, args)
{
	new Handle:DP = CreateDataPack();
	
	WritePackCell(DP, GetClientUserId(client));
	WritePackCell(DP, CM_ShowTopPlayers);
	
	SQL_GetTopPlayers(0, DP);
	
	return Plugin_Handled;
}


public SQL_ChangeDatabases(Database db, DBResultSet hResults, const char[] Error, Handle:DP) 
{ 
    /* If something fucked up. */ 
    if (hResults == null) 
        ThrowError(Error); 
		
	else
	{
		ResetPack(DP);
		
		
		new client = GetClientOfUserId(ReadPackCell(DP));
		new clientprefWins = ReadPackCell(DP);
		
		new String:SteamID[35];
		ReadPackString(DP, SteamID, sizeof(SteamID));
		
		CloseHandle(DP);
		if(client != 0)
			SetClientLRWins(client, 0);
			
		else
		{ 
			new String:sQuery[256];
			
			Format(sQuery, sizeof(sQuery), "UPDATE LastRequest_players SET wins = wins + %i WHERE SteamID = \"%s\"", clientprefWins, SteamID);
			
			dbLRWins.Query(SQL_Error, sQuery);
		}
	}
} 
/* // sm
public Action:Command_LRManage(client, args)
{
	if(get_user_flags(id) & ADMIN_IMMUNITY)
	{
		new LRManageMenu = menu_create("\y[Last Request]\w Choose what to do:", "HandleShowLRManageMenu");
		
		menu_additem(LRManageMenu, "Add Teleport");
		menu_additem(LRManageMenu, "Remove Teleport");
		
		menu_display(id, LRManageMenu);
	}
}	

public HandleShowLRManageMenu(id, LRManageMenu, item)
{
	if(item == MENU_EXIT) return;
	
	switch(item + 1)
	{
		case 1: ShowAddTeleportMenu(id);
		case 2: ShowRemoveTeleportMenu(id);
	}
}

public ShowAddTeleportMenu(id)
{
	new Format[64];
	new AddTeleport = menu_create("\y[Last Request]\wChoose parameters:", "HandleCmdAddTeleport");
	
	formatex(Format, sizeof(Format), "Origin T:\r %i %i %i", OriginT[0][id], OriginT[1][id], OriginT[2][id]);
	menu_additem(AddTeleport, Format);
	
	formatex(Format, sizeof(Format), "Origin CT:\r %i %i %i", OriginCT[0][id], OriginCT[1][id], OriginCT[2][id]);
	menu_additem(AddTeleport, Format);
	
	formatex(Format, sizeof(Format), "Duel Name:\y %s", DuelN[id]);
	menu_additem(AddTeleport, Format);
	
	menu_additem(AddTeleport, "\rAdd The Teleport");
	
	menu_display(id, AddTeleport);
	
	return 1;
}

public HandleCmdAddTeleport(id, AddTeleport, item)
{	
	if(item == MENU_EXIT) return;
	
	switch(item+1)
	{
		case 1: client_cmd(id, "^"LRManage_TOrigin^"");
		case 2: client_cmd(id, "^"LRManage_CTOrigin^"");
		case 3: client_cmd(id, "^"LRManage_DuelName^"");
	}
	if(item + 1 < 3)
	{
		ShowAddTeleportMenu(id);
		return;
	}
	if(item + 1 == 3)
		return;
		
	new Format[100], bool:Can = true;
	
	for(new i;i < 3;i++)
		if(OriginT[i][id] == 0 || OriginCT[i][id] == 0) Can = false;
	
	if(equali(DuelN[id], "")) Can = false;
	
	new ReadFile[200], Token[3][200], TOrigin[200], CTOrigin[200], Duel[200], Line, Length;
	
	while(read_file(TPDir, Line++, ReadFile, sizeof(ReadFile), Length))
	{
		if(!read_file(TPDir, Line, ReadFile, sizeof(ReadFile), Length))
		{
			break;
		}

		if(ReadFile[0] == ';' || strcmp(ReadFile, "") == 0) continue;
		
		strtok(ReadFile, TOrigin, 199, Token[0], 199, '=');
		strtok(Token[0], CTOrigin, 199, Duel, 199, '=');
		
		remove_quotes(Duel);
		
		if(strcmp(Duel, DuelN[id]) == 0) Can = false;
	}
	if(Can)
	{
		formatex(Format, sizeof(Format), "\n%i %i %i=%i %i %i=^"%s^"", OriginT[0][id], OriginT[1][id], OriginT[2][id], OriginCT[0][id], OriginCT[1][id], OriginCT[2][id], DuelN[id]);
		write_file(TPDir, Format);
		client_print(id, print_chat, "Teleport was added successfully!");
		DuelN[id] = "";
	}
}

public ShowRemoveTeleportMenu(id)
{	
	if(get_user_flags(id) & ADMIN_RCON)
	{
		new ReadFile[200], Token[3][200], TOrigin[200], CTOrigin[200], Duel[200], Format[500], Line, Length;
		new RemoveTeleport = menu_create("\y[Last Request]\wChoose a teleport to remove:", "HandleShowRemoveTeleportMenu");
		
		while(read_file(TPDir, Line++, ReadFile, sizeof(ReadFile), Length))
		{
			if(!read_file(TPDir, Line, ReadFile, sizeof(ReadFile), Length))
			{
				menu_display(id, RemoveTeleport, 0);
				break;
			}
	
			if(ReadFile[0] == ';' || strcmp(ReadFile, "") == 0) continue;
			
			strtok(ReadFile, TOrigin, 199, Token[0], 199, '=');
			strtok(Token[0], CTOrigin, 199, Duel, 199, '=');
			
			remove_quotes(Duel);
			
			new String[10];
			
			num_to_str(Line, String, sizeof(String));
			formatex(Format, sizeof(Format), Duel), menu_additem(RemoveTeleport, Format, String);
		}
	}
}

public HandleShowRemoveTeleportMenu(id, RemoveTeleport, item)
{
	if(item == MENU_EXIT) return;
		
	new data[6], Name[64], access, callback;
	
	menu_item_getinfo(RemoveTeleport, item, access, data, sizeof( data ), Name, sizeof(Name), callback);
	
	new ConfirmMenu = menu_create("\y[Last Request]\wAre you sure?", "HandleCmdRemoveTeleport");
	
	menu_additem(ConfirmMenu, "Yes", data);
	menu_additem(ConfirmMenu, "No");
	
	menu_display(id, ConfirmMenu);
	
}
public HandleCmdRemoveTeleport(id, ConfirmMenu, item)
{
	if(item == MENU_EXIT || item == 1) return;
	
	new data[6], Name[64], access, callback;
	
	menu_item_getinfo(ConfirmMenu, item, access, data, sizeof( data ), Name, sizeof(Name), callback);
	
	new ReadFile[100], Length, Line;
	
	while(read_file(TPDir, Line++, ReadFile, sizeof(ReadFile), Length))
	{
		if(Line == str_to_num(data))
			write_file(TPDir, "", str_to_num(data));
	}
	client_print(id, print_chat, "Teleport was removed successfully!");
	menu_destroy(ConfirmMenu);
}	

public SetTOrigin(id)
{
	new Origin[3];
	get_user_origin(id, Origin);
	
	OriginT[0][id] = Origin[0];
	OriginT[1][id] = Origin[1];
	OriginT[2][id] = Origin[2];
	ShowAddTeleportMenu(id);
}

public SetCTOrigin(id)
{
	new Origin[3];
	get_user_origin(id, Origin);
	
	OriginCT[0][id] = Origin[0];
	OriginCT[1][id] = Origin[1];
	OriginCT[2][id] = Origin[2];
	ShowAddTeleportMenu(id);
}

public SetDuelName(id)	ShowDuelNames(id);

public ShowDuelNames(id)
{
	new DuelNamesMenu = menu_create("\y[Last Request]\wChoose duel to teleport:", "HandleShowDuelNames");
	
	menu_additem(DuelNamesMenu, "Shot4Shot Duels");
	menu_additem(DuelNamesMenu, "Custom War");
	menu_additem(DuelNamesMenu, "Fun Duels");
	menu_additem(DuelNamesMenu, "Auto Duels");
	
	menu_display(id, DuelNamesMenu);
}	

public HandleShowDuelNames(id, DuelNamesMenu, item)
{
	if(item == MENU_EXIT) return;
	
	switch(item + 1)
	{
		case 1, 2: TypeDuel[id] = item, ShowWeaponDuelNames(id);
		case 3: ShowFunDuelNames(id);
		case 4: ShowAutoDuelNames(id);
	}
}
	
public ShowWeaponDuelNames(id) // This is to set teleportation.
{
	new Format[100];
	
	formatex(Format, sizeof(Format), "\y[Last Request]\w Choose teleportations for\y %s", TypeDuel[id] == 0 ? "Shot4Shot" : "Custom Duel");
	new WeaponMenu = menu_create(Format, "HandleShowWeaponDuelNames");

	menu_additem(WeaponMenu, "Deagle");
	menu_additem(WeaponMenu, "AWP");
	menu_additem(WeaponMenu, "SSG 08");
	menu_additem(WeaponMenu, "USP");
	menu_additem(WeaponMenu, "Fiveseven");
	menu_additem(WeaponMenu, "M4A1");
	menu_additem(WeaponMenu, "AK47");
	
	
	if(TypeDuel[id] == 1)
	{
		menu_additem(WeaponMenu, "HE Grenade");
		menu_additem(WeaponMenu, "\rKnife");
	}
	
	menu_display(id, WeaponMenu);
}

public HandleShowWeaponDuelNames(id, WeaponMenu, item)
{
	if(item == MENU_EXIT) ShowLRManageMenu(id);

	if(TypeDuel[id] == 0)
	{
		DuelN[id] = "S4S";
		
		return ShowAddTeleportMenu(id);
	}
	else DuelN[id] = "Custom | ";
	
	switch(item + 1)
	{
		case 1:	add(DuelN[id], 99, "Deagle");
		
		case 2:	add(DuelN[id], 99, "AWP");
		
		case 3:	add(DuelN[id], 99, "SSG 08");
		
		case 4:	add(DuelN[id], 99, "USP");
		
		case 5:	add(DuelN[id], 99, "Fiveseven");
		
		case 6:	add(DuelN[id], 99, "M4A1");
		
		case 7:	add(DuelN[id], 99, "AK47");
		
		case 8:	add(DuelN[id], 99, "HE");
		
		case 9: add(DuelN[id], 99, "Knife");
	}
	
	ShowAddTeleportMenu(id);
	
	return 0;
}	

public ShowFunDuelNames(id)
{
	new FunDuels = menu_create("\y[Last Request]\w Choose teleportations for\y Fun Duels", "HandleShowFunDuelNames");
	
	menu_additem(FunDuels, "Night Crawler");
	menu_additem(FunDuels, "Shark");
	menu_additem(FunDuels, "Hide'N'Seek");
	//menu_additem(FunDuels, "Gun Toss");
	//menu_additem(FunDuels, "Shoot The Bomb");
	//menu_additem(FunDuels, "Spray");
	menu_additem(FunDuels, "Super Deagle");
	menu_additem(FunDuels, "Smoke Death Duel");
	menu_additem(FunDuels, "Soccer");
	menu_additem(FunDuels, "KZ");
	
	if(MapOkay)
		menu_additem(FunDuels, "Jump");
		
	//menu_additem(FunDuels, "Freeday");
	 
	menu_display(id, FunDuels);
}

public HandleShowFunDuelNames(id, FunDuels, item)
{
	if(item == MENU_EXIT) return;
	
	switch(item + 1)
	{
		case 1: DuelN[id] = "Fun | Night Crawler";
			
		case 2: DuelN[id] = "Fun | Shark";
			
		case 3: DuelN[id] = "Fun | HNS";
		
		case 4:	DuelN[id] = "Fun | Super Deagle";
		
		case 5:	DuelN[id] = "Fun | Smoke Death Duel";
	
		case 6:	DuelN[id] = "Fun | Soccer";
		
		case 7:  DuelN[id] = "Fun | KZ";
		
		case 8:  if(MapOkay) DuelN[id] = "Fun | Jump";
	}
	
	ShowAddTeleportMenu(id);
}

public ShowAutoDuelNames(id)
{
	new AutoDuels = menu_create("\y[Last Request]\w Choose teleportations for\y Auto Duels", "HandleShowAutoDuelNames");
	
	menu_additem(AutoDuels, "Shoot The Bomb");
	menu_additem(AutoDuels, "Spray");
	 
	menu_display(id, AutoDuels);
}

public HandleShowAutoDuelNames(id, AutoDuels, item)
{
	if(item == MENU_EXIT) return;
	
	switch(item + 1)
	{	
		case 1:	DuelN[id] = "Auto | Shoot The Bomb";
		
		case 2:	DuelN[id] = "Auto | Spray";
	}
	
	ShowAddTeleportMenu(id);
}	
*/
public Action:Event_PlayerDeath(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	if(!LRStarted)
	{
		CheckAnnounceLR();
		return;
	}
	
	// LRStarted
	
	new victim = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
	
	new bool:victimct, bool:norambo;
	
	if(GetClientTeam(victim) == CS_TEAM_CT) victimct = true;
	
	if(!Rambo && LRStarted) norambo = true;
	
	
	SetHudMessage(-1.0, -1.0, 5.0, 127, 255, 127);
	
	if(norambo)
	{
		if(GetPlayerCount() >= 5)
			SQL_AddClientLRWins(attacker);
		
		else
			PrintToChat(attacker, "%s \x07LR \x01Wins are registered only with \x075 \x01players or above.", PREFIX);
			
		if(Gangs_HasGang(attacker) && GetPlayerCount() >= 5)
		{
			new String:GangName[64];
			Gangs_GetClientGangName(attacker, GangName, sizeof(GangName));
			
			Gangs_GiveGangCredits(GangName, 100);
			Gangs_AddClientDonations(attacker, 100);
			
			Gangs_PrintToChatGang(GangName, " \x05%N \x01has earned \x07100 \x01credits for his gang by winning an \x07LR!", attacker);
		}
	}	
	
	ShowHudMessage(0, HUD_WIN, "%N\nhas won the duel against\n%N", victimct ? Prisoner : Guard, victimct ? Guard : Prisoner);
	PrintToChatAll("%s \x05%N \x01has won the LR against \x07%N!", PREFIX, victimct ? Prisoner : Guard, victimct ? Guard : Prisoner);

	if(LRPart(victim) && norambo)
	{
		EndLR();
		
		if(victimct)
		{
			LRAnnounced = false;
			CheckAnnounceLR();
			
			for(new i=1;i <= MaxClients;i++)
			{
				if(!IsClientInGame(i))
					continue;
				
				SetClientGodmode(i);
				
			}
		}
	}
}	

CheckAnnounceLR()
{
	if(LRAnnounced)
		return;
		
	new T, CT, LastOne;
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(!IsPlayerAlive(i))
			continue;
			
		switch(GetClientTeam(i))
		{
			case CS_TEAM_T:
			{
				LastOne = i;
				T++;
			}
			case CS_TEAM_CT:
			{
				CT++;
			}
		}
	}	
	
	if(T == 1 && CT > 0)
	{
		Command_LR(LastOne, 0);
		
		if(TIMER_KILLCHOKINGROUND != INVALID_HANDLE)
		{
			CloseHandle(TIMER_KILLCHOKINGROUND);
			TIMER_KILLCHOKINGROUND = INVALID_HANDLE;
		}	
		
		ChokeTimer = GetConVarInt(hcv_TimeMustBeginLR) + 1;
		TriggerTimer(TIMER_KILLCHOKINGROUND = CreateTimer(1.0, Timer_CheckChokeRound, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE), true);
		
		if(!g_bLRSound)
		{
			PlaySoundToAll(LR_SOUNDS_DIRECTORY);
			g_bLRSound = true;
		}
	}
}

public Action:Timer_CheckChokeRound(Handle:hTimer)
{
	new String:Message[256];
	Call_StartForward(fw_CanStartLR);
		
	Call_PushCell(GetRandomAlivePlayer(CS_TEAM_T));
	Call_PushStringEx(Message, sizeof(Message), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(hTimer);
	
	new Action:Value
	Call_Finish(Value);
	
	if(Value >= Plugin_Changed)
	{
		TIMER_KILLCHOKINGROUND = INVALID_HANDLE;
		
		return Plugin_Stop;
	}	
	ChokeTimer--;
	
	if(ChokeTimer == 0)
	{
		TIMER_KILLCHOKINGROUND = INVALID_HANDLE;

		Prisoner = GetRandomAlivePlayer(CS_TEAM_T);
		Guard = GetRandomAlivePlayer(CS_TEAM_CT);
		
		if(Prisoner == 0 || Guard == 0)
			return Plugin_Stop;
			
		PrintToChatAll("%s \x01Prisoner \x05%N \x01died for not starting \x07LR! ", PREFIX, Prisoner);
		
		LRStarted = true;
		
		FinishHim(Prisoner, Guard);
		
		LRStarted = false;
		
		return Plugin_Stop;
	}
	
	
	PrintCenterTextAll("<font color='#FFFFFF'>Prisoner must start LR within </font><font color='#FF0000'>%i</font> <font color='#FFFFFF'>seconds or he will die.</font><font color='#FF0000'></font>", ChokeTimer);
	
	return Plugin_Continue;
}
public Action:Event_PlayerTeam(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(LRPart(client))
	{
		EndLR();
	}
}	

public Action:Event_PlayerHurt(Handle:hEvent, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(LRPart(client))
	{	
		// Blocks all forms of healing.
		SetEntityMaxHealth(client, GetEntityHealth(client));
	}
}

public BitchSlapBackwards(victim, weapon, Float:strength) // Stole the dodgeball tactic from https://forums.alliedmods.net/showthread.php?t=17116
{
	new Float:origin[3], Float:velocity[3];
	GetEntPropVector(weapon, Prop_Data, "m_vecOrigin", origin);
	GetVelocityFromOrigin(victim, origin, strength, velocity);
	velocity[2] = strength / 10.0;
	
	TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, velocity);
}

public Action:Event_TakeDamageAlive(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if(!LRStarted)
		return Plugin_Continue;
	
	else if(BypassBlockers)
		return Plugin_Continue;
		
	else if(attacker == Prisoner && victim != Guard && GetClientTeam(victim) == CS_TEAM_CT && !Rambo && !LRPart(victim))
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	
		
	new bool:suicide;
	
	if( ( attacker != Guard && victim == Prisoner ) || ( attacker != Prisoner && victim == Guard ) ) suicide = true; // Whether the player is killed by the guard or by himself, it is still okay to activate.
	
	if(suicide && LRPart(victim) && damage >= GetEntityHealth(victim) && ( !IsPlayer(attacker) || attacker == victim ) )
	{
		if(Rambo && GetClientTeam(victim) == CS_TEAM_CT)
			Guard = victim;
		
		if(Guard == victim)
			FinishHim(victim, Prisoner);
			
		else 
			FinishHim(victim, Guard);
			
		damage = 0.0;
		return Plugin_Changed;
	}
	
	if(!IsPlayer(attacker))
		return Plugin_Continue;
	
	if(LRPart(attacker) && LRPart(victim))
	{
		if(StrContains(DuelName, "Super Deagle") != -1)
			BitchSlapBackwards(victim, attacker, 5150.0);
	
		if(Dodgeball)
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	
		if(Ring)
		{
			new Float:Position[3], Float:Angles[3];
			GetClientEyePosition(attacker, Position); 
			GetClientEyeAngles(attacker, Angles); 
			
			TR_TraceRayFilter(Position, Angles, MASK_SHOT, RayType_Infinite, Trace_HitVictimOnly, victim); //Start the trace 
			
			new bool:headshot = (TR_GetHitGroup() == 1); //Get the hit group, 1 means headshot
			damage = 0.0;
			
			if(headshot)
				BitchSlapBackwards(victim, attacker, 625.0);
				
			else
				BitchSlapBackwards(victim, attacker, 375.0);
				
			return Plugin_Changed;
		}
	
	}
	else if(!Rambo)
	{
		damage = 0.0;
		
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public Event_TakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype)
{
	if(!LRStarted)
		return;
		
	else if(!LRPart(victim))
		return;
		
	else if(!Bleed)
		return;
		
	if(victim == Guard)
		BleedTarget = Guard;
		
	else if(victim == Prisoner)
		BleedTarget = Prisoner;
		
	TriggerTimer(TIMER_COUNTDOWN, true);
}
public Action:LostDodgeball(Handle:hTimer, victim)
{
	if(!LRStarted)
		return Plugin_Continue;
		
	else if(!IsPlayerAlive(Prisoner) || !IsPlayerAlive(Guard))
		return Plugin_Continue;
		
	if(victim == Prisoner)
		FinishHim(Prisoner, Guard);
		
	else if(victim == Guard)
		FinishHim(Guard, Prisoner);
		
	return Plugin_Continue;
}

public Action:Event_TraceAttack(victim, &attacker, &inflictor, &Float:damage, &damagetype, &ammotype, hitbox, hitgroup)
{
	if(!LRStarted)
		return Plugin_Continue;
		
	else if(!LRPart(attacker))
		return Plugin_Continue;

	new weapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
		
	new String:Classname[50];
	GetEdictClassname(weapon, Classname, sizeof(Classname));
	if(strncmp(Classname, "weapon_knife", 12) == 0)
	{	
		if(damage < 69 && HeadShot) // Knife should deal 76 max.
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	}
	else if(hitgroup != 1 && HeadShot)
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public bool:Trace_HitVictimOnly(entity, contentsMask, victim) 
{ 
	return entity == victim; 
}  

public bool:Trace_DontHitPlayers(entity, contentsMask)
{
	return !IsPlayer(entity);
}

public Action:Event_ShouldInvisible(client, viewer)
{
	if(client == viewer)
		return Plugin_Continue;
		
	if(!LRStarted)
		return Plugin_Continue;
		
	else if(StrContains(DuelName, "Night Crawler") == -1)
		return Plugin_Continue;
	
	else if(GetClientTeam(client) == GetClientTeam(viewer))
		return Plugin_Continue;
		
	else if(Prisoner != client)
		return Plugin_Continue;
		
	return Plugin_Handled;
}
/*
public _Ham_TraceAttack(victim, attacker, Float:damage, Float:direction[3], traceresult, damagebits)
{
	
	if(get_tr2(traceresult, TR_iHitgroup) == HIT_HEAD || !HeadShot || !LRStarted)
		return HAM_IGNORED;
	
	return HAM_SUPERCEDE;	
}

public _Ham_Touch(victim, attacker)
{
	if(!LRStarted)
		return HAM_IGNORED;
		
	else if(!pev_valid(victim) || !IsValidPlayer(attacker))
		return HAM_IGNORED;
		
	else if(!LRPart(attacker))
		return HAM_IGNORED;
	
	else if(!is_user_alive(attacker))
		return HAM_IGNORED;
	
	else if(GunToss)
		return HAM_SUPERCEDE;
	
	new Class[15];
	entity_get_string(victim, EV_SZ_classname, Class, sizeof(Class));
	if(equali(Class, "weaponbox"))
	{
		if(GetWeaponBoxWeaponType(victim) == SecNum || GetWeaponBoxWeaponType(victim) == PrimNum || GetWeaponBoxWeaponType(victim) == CSWeapon_C4)
			return HAM_IGNORED;
	}
	
	return HAM_SUPERCEDE;
}
*/

public OnClientDisconnect(client)
{
	if(LRPart(client))
		EndLR();
}

public OnClientPostAdminCheck(client)
{
	if(!IsFakeClient(client))
		SQL_GetClientLRWins(client);
}

public OnClientPutInServer(client)
{
	ShowMessage[client] = true;
	SDKHook(client, SDKHook_OnTakeDamageAlive, Event_TakeDamageAlive);
	SDKHook(client, SDKHook_OnTakeDamagePost, Event_TakeDamagePost);
	SDKHook(client, SDKHook_TraceAttack, Event_TraceAttack);
	SDKHook(client, SDKHook_SetTransmit, Event_ShouldInvisible);
	SDKHook(client, SDKHook_PreThink, Event_PlayerPreThink);
	SDKHook(client, SDKHook_PreThinkPost, Event_Think);
	SDKHook(client, SDKHook_PostThink, Event_Think);
	SDKHook(client, SDKHook_PostThinkPost, Event_Think);
	SDKHook(client, SDKHook_WeaponCanUse, Event_WeaponPickUp);
	SDKHook(client, SDKHook_WeaponEquipPost, Event_WeaponEquipPost);
	SDKHook(client, SDKHook_WeaponSwitch, Event_WeaponSwitch);
}

public OnClientCookiesCached(client)
{
	ShowMessage[client] = GetClientInfoMessage(client);
}

public Action:Event_WeaponPickUp(client, weapon) 
{
	if(!LRStarted)
		return Plugin_Continue;

	else if(!LRPart(client))
		return Plugin_Continue;
	
	else if(Rambo)
		return Plugin_Continue;
		
	decl String:WeaponName[32]; 
	GetEdictClassname(weapon, WeaponName, sizeof(WeaponName)); 
	
	if(StrEqual(WeaponName, "weapon_c4", true))
		return Plugin_Continue;
	/*
	if(StrEqual(WeaponName, "weapon_hkp2000", true))
		WeaponName = "weapon_usp_silencer";

	if(StrEqual(WeaponName, "weapon_m4a1_silencer", true))
		WeaponName = "weapon_m4a1";
	*/
	new bool:HNS;
	
	if(StrContains(DuelName, "HNS") != -1 || StrContains(DuelName, "Night Crawler") != -1 || StrContains(DuelName, "Shark") != -1) HNS = true;
	
	if(HNS && Prisoner == client && strncmp(WeaponName, "weapon_knife", 12) != 0)
	{
		AcceptEntityInput(weapon, "Kill");
		return Plugin_Handled;
	}	
	if(HNS && client == Guard && strncmp(WeaponName, "weapon_knife", 12) == 0)
	{
		AcceptEntityInput(weapon, "Kill");
		return Plugin_Handled;
	}
	
	if(StrEqual(PrimWep, WeaponName, true) || StrEqual(SecWep, WeaponName, true))
	{
		if(!GunToss)
			return Plugin_Continue;
			
		else
		{
			if(GetClientButtons(client) & IN_USE || AllowGunTossPickup)
				return Plugin_Continue;

			return Plugin_Handled;
		}
	}	
	
	new PrimDefIndex, SecDefIndex;
	
	if(PrimNum != CSWeapon_NONE) PrimDefIndex = CS_WeaponIDToItemDefIndex(PrimNum);
	if(SecNum != CSWeapon_NONE) SecDefIndex = CS_WeaponIDToItemDefIndex(SecNum);
	
	new WeaponDefIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	
	if(PrimDefIndex == WeaponDefIndex || SecDefIndex == WeaponDefIndex)
	{
		if(!GunToss)
			return Plugin_Continue;
			
		else
		{
			if(GetClientButtons(client) & IN_USE || AllowGunTossPickup)
				return Plugin_Continue;

			return Plugin_Handled;
		}
	}
	AcceptEntityInput(weapon, "Kill");
	return Plugin_Handled;
}

public Action:Event_WeaponEquipPost(client, weapon) // This function is purely to solve !ws issues.
{
	if(!LRStarted)
		return Plugin_Continue;
		
	else if(!LRPart(client))
		return Plugin_Continue;
		
	new String:Classname[50];
	
	GetEntityClassname(weapon, Classname, sizeof(Classname));
	
	decl String:WeaponName[32]; 
	GetEdictClassname(weapon, WeaponName, sizeof(WeaponName)); 
		
	if(StrEqual(WeaponName, "weapon_hkp2000", true))
		WeaponName = "weapon_usp_silencer";

	if(StrEqual(WeaponName, "weapon_m4a1_silencer", true))
		WeaponName = "weapon_m4a1";
		
	if(StrEqual(Classname, PrimWep))
	{
		if(Prisoner == client)
			PrisonerPrim = weapon;
			
		else 
			GuardPrim = weapon;
	}
	
	else if(StrEqual(Classname, SecWep))
	{
		if(Prisoner == client)
			PrisonerSec = weapon;
			
		else 
			GuardSec = weapon;
	}
	
	if(GunToss)
		DroppedDeagle[client] = false;
	
	return Plugin_Continue;
}

public Action:Event_WeaponSwitch(client, weapon) // This function is purely to solve !ws issues.
{
	//if(weapon == -1)
		//return Plugin_Continue;
		
	SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);

	return Plugin_Continue;
}

stock EndLR(EndTimers = true)
{
	Prisoner = -1;
	Guard = -1;

	PrimWep = "";
	PrimNum = CSWeapon_NONE;
	SecWep = "";
	SecNum = CSWeapon_NONE;
	Zoom = true;
	HeadShot = false;
	Duck = true;
	Jump = true;
	NoRecoil = false;
	
	if(EndTimers)
		FinishTimers();
	
	
	firstwrites = false;
	combo_started = false;
	firstlisten = false;
	mathcontest = false;
	opposite = false;
	typestages = false;
	firstwritesmoveable = false;
	combomoveable = false;
	firstlistenmoveable = false;
	mathcontestmoveable = false;
	oppositemoveable = false;
	typestagesmoveable = false;
	//GuardSprayHeight = 0.0;
	//PrisonerSprayHeight = 0.0;
	GuardThrown = false;
	PrisonerThrown = false;
	Ring = false;
	Dodgeball = false;
	MostJumps = false;
	mostjumpscountdown = 0;
	mostjumpsmovable = false;
	GuardJumps = 0;
	PrisonerJumps = 0;
	GunToss = false;
	Bleed = false;
	
	Rambo = false;
	
	bDropBlock = false;
	
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
		
		if(LRStarted)
		{
			SetEntityHealth(i, 100);
			
			StripPlayerWeapons(i);
			GivePlayerItem(i, "weapon_knife");
			
			if(GetClientTeam(i) == CS_TEAM_CT)
				GivePlayerItem(i, "weapon_m4a1");
		}
		SetClientNoclip(i, false);
		SetClientGodmode(i, false);
		SetEntityGlow(i);
		
		JumpOrigin[i] = NULL_VECTOR;
		AdjustedJump[i] = false;
		GroundHeight[i] = 0.0;
		CanSetHealth[i] = false;
		
		if(!IsFakeClient(i))
			SendConVarValue(i, hcv_NoSpread, "0");
	}
	
	ResetConVar(hcv_NoclipSpeed);
	
	BypassBlockers = false;
	
	LRStarted = false;
}

FinishTimers(Handle:hTimer_Ignore = INVALID_HANDLE)
{
	if(TIMER_COUNTDOWN != INVALID_HANDLE && TIMER_COUNTDOWN != hTimer_Ignore)
	{
		CloseHandle(TIMER_COUNTDOWN);
		TIMER_COUNTDOWN = INVALID_HANDLE;
	}
	if(TIMER_INFOMSG != INVALID_HANDLE && TIMER_INFOMSG != hTimer_Ignore)
	{
		CloseHandle(TIMER_INFOMSG);
		TIMER_INFOMSG = INVALID_HANDLE;
	}
	
	for(new i=1;i < MAXPLAYERS+1;i++)
	{
		if(TIMER_BEACON[i] != INVALID_HANDLE && TIMER_BEACON[i] != hTimer_Ignore)
		{
			CloseHandle(TIMER_BEACON[i]);
			TIMER_BEACON[i] = INVALID_HANDLE;
		}
	}
	if(TIMER_FAILREACTION != INVALID_HANDLE && TIMER_FAILREACTION != hTimer_Ignore)
	{
		CloseHandle(TIMER_FAILREACTION);
		TIMER_FAILREACTION = INVALID_HANDLE;
	}
	if(TIMER_REACTION != INVALID_HANDLE && TIMER_REACTION != hTimer_Ignore)
	{
		CloseHandle(TIMER_REACTION);
		TIMER_REACTION = INVALID_HANDLE;
	}
	if(TIMER_SLAYALL != INVALID_HANDLE && TIMER_SLAYALL != hTimer_Ignore)
	{
		CloseHandle(TIMER_SLAYALL);
		TIMER_SLAYALL = INVALID_HANDLE
	}
	if(TIMER_MOSTJUMPS != INVALID_HANDLE && TIMER_MOSTJUMPS != hTimer_Ignore)
	{
		CloseHandle(TIMER_MOSTJUMPS);
		TIMER_MOSTJUMPS = INVALID_HANDLE;
	}
	if(TIMER_100MILISECONDS != INVALID_HANDLE && TIMER_100MILISECONDS != hTimer_Ignore)
	{
		CloseHandle(TIMER_100MILISECONDS);
		TIMER_100MILISECONDS = INVALID_HANDLE;
	}
	if(TIMER_KILLCHOKINGROUND != INVALID_HANDLE && TIMER_KILLCHOKINGROUND != hTimer_Ignore)
	{
		CloseHandle(TIMER_KILLCHOKINGROUND);
		TIMER_KILLCHOKINGROUND = INVALID_HANDLE;
	}
}

public Action:Command_LR(client, args)
{
	if(GetClientTeam(client) == CS_TEAM_CT)
	{
		new LastT, count;
		for(new i=1;i <= MaxClients;i++)
		{
			if(!IsClientInGame(i))
				continue;
				
			else if(!IsPlayerAlive(i))
				continue;
				
			LastT = i;
			count++;
		}
		
		if(count == 1)
		{
			PrintToChatAll("%N has shown the last T the LR menu!", client);
			
			Command_LR(LastT, 0);
		}
		
	}
	if(LastRequest(client))
	{
		EndLR(false);
	
		new Handle:hMenu = CreateMenu(LR_MenuHandler);

		AddMenuItem(hMenu, "", "Shot4Shot Duels");
		AddMenuItem(hMenu, "", "Custom War");
		AddMenuItem(hMenu, "", "Fun Duels");
		AddMenuItem(hMenu, "", "Auto Duels");
		AddMenuItem(hMenu, "", "RAMBO REBEL");
		AddMenuItem(hMenu, "", "Random");
		AddMenuItem(hMenu, "", "Random no Rambo Rebel");
		
		SetMenuTitle(hMenu, "[GlowX-LR] Select your favorite duel!");
		
		SetMenuPagination(hMenu, MENU_NO_PAGINATION);
		SetMenuExitButton(hMenu, true);
		
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
		CanSetHealth[client] = false;
	}
	
	return Plugin_Handled;
}

public LR_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		
		if(!LastRequest(client))
		{
			hMenu = INVALID_HANDLE;
			return;
		}
		new T;
		
		for(new i=1;i <= MaxClients;i++)
		{
			if(!IsClientInGame(i))
				continue;
				
			if(GetClientTeam(i) == CS_TEAM_T)
				T++;
		}	
		
		switch(item + 1)
		{
			case 1: 
			{
				DuelName = "S4S";
				ShowWeaponMenu(client);
			}
			
			case 2:
			{
				PrimWep = "weapon_m4a1";
				PrimNum = CSWeapon_M4A1;
				Zoom = true;
				HeadShot = false;
				BPAmmo = 10000;
				HPamount = 1000;
				Vest = 2;
				DuelName = "S4S | M4A1";
				ShowCustomMenu(client);
			}
			
			case 3: ShowFunMenu(client);
			
			case 4: ShowAutoMenu(client);
			
			case 5:
			{
				if(LastRequest(client))
				{
					if(T >= 3)
					{
				
						Prisoner = client;
						DuelName = "RAMBO REBEL";
						LRStarted = true;
						Vest = 2;

						//OpenAllCells();
						FinishTimers();
						StartRambo();
						
						// BAR COLOR!!!
						PrintToChatAll("%s \x01%s \x07%N \x01vs \x07%N", PREFIX, DuelName, Prisoner, Guard);
						PrintToChatAll("%s \x01%s \x07%N \x01vs \x07%N", PREFIX, DuelName, Prisoner, Guard);
						PrintToChatAll("%s \x01%s \x07%N \x01vs \x07%N", PREFIX, DuelName, Prisoner, Guard);
					}
					else
						PrintToChat(client, "%s You can only start Rambo when there are \x073 \x01or more total terror.", PREFIX);
				}
			}
		
			case 6:
			{
				LR_MenuHandler(INVALID_HANDLE, MenuAction_Select, client, GetRandomInt(0, 4));
			}
			case 7:
			{
				LR_MenuHandler(INVALID_HANDLE, MenuAction_Select, client, GetRandomInt(0, 3));
			}
		}	
		
		hMenu = INVALID_HANDLE;
	}
}

public ShowWeaponMenu(client)
{
	new Type;
	if(StrContains(DuelName, "S4S") != -1)
	{
		Type = 0;
	}
	else if(StrContains(DuelName, "Custom") != -1)
	{
		Type = 1;
	}
	new String:TempFormat[100];
	
	new Handle:hMenu = CreateMenu(Weapons_MenuHandler);

	AddMenuItem(hMenu, "", "Glock-18");
	AddMenuItem(hMenu, "", "USP");
	AddMenuItem(hMenu, "", "Dual Berretas");
	AddMenuItem(hMenu, "", "P250");
	AddMenuItem(hMenu, "", "Fiveseven");
	AddMenuItem(hMenu, "", "Tec-9");
	AddMenuItem(hMenu, "", "Deagle");
	AddMenuItem(hMenu, "", "Revolver");
	
	if(StrContains(DuelName, "Custom") != -1)
	{
		AddMenuItem(hMenu, "", "HE Grenade");
		AddMenuItem(hMenu, "", "Knife");
	}
	
	AddMenuItem(hMenu, "", "Random");
	
	Format(TempFormat, sizeof(TempFormat), "[Last Request] %s:", Type == 0 ? "Shot4Shot" : "Custom Duel");
	SetMenuTitle(hMenu, TempFormat);
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Weapons_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		if(!LastRequest(client))
		{
			hMenu = INVALID_HANDLE;
			return;
		}
		new Type; // S4S = 0, Custom = 1
		PrimNum = CSWeapon_NONE;
		SecNum = CSWeapon_NONE;
	
		if(StrContains(DuelName, "S4S") != -1)
		{
			Type = 0;
		}
		else if(StrContains(DuelName, "Custom") != -1)
		{
			Type = 1;
		}
		switch(item + 1)
		{
			case 1:
			{
				DuelName = "S4S | Glock-18";
				PrimWep = "weapon_glock";
				PrimNum = CSWeapon_GLOCK;
			}
			case 2:
			{
				DuelName = "S4S | USP";
				PrimWep = "weapon_usp_silencer";
				PrimNum = CSWeapon_USP_SILENCER;
			}
			case 3:
			{
				DuelName = "S4S | Dual-Berretas";
				PrimWep = "weapon_elite";
				PrimNum = CSWeapon_ELITE
			}
			case 4:
			{
				DuelName = "S4S | P250";
				PrimWep = "weapon_p250";
				PrimNum = CSWeapon_P250;
			}
			case 5:
			{
				DuelName = "S4S | Fiveseven";
				PrimWep = "weapon_fiveseven";
				PrimNum = CSWeapon_FIVESEVEN;
			}
			case 6:
			{
				DuelName = "S4S | Tec-9";
				PrimWep = "weapon_tec9";
				PrimNum = CSWeapon_TEC9;
			}
			case 7:
			{
				DuelName = "S4S | Deagle";
				PrimWep = "weapon_deagle";
				PrimNum = CSWeapon_DEAGLE;
			}
			case 8:
			{
				DuelName = "S4S | Revolver";
				PrimWep = "weapon_revolver";
				PrimNum = CSWeapon_REVOLVER;
			}
			
			case 9:
			{
				if(Type == 1)
				{
					DuelName = "S4S | HE Grenade";
					PrimWep = "weapon_hegrenade";
					PrimNum = CSWeapon_HEGRENADE;
				}
				else
				{
					Weapons_MenuHandler(INVALID_HANDLE, MenuAction_Select, client, GetRandomInt(0, 7));
				}
			}
			
			case 10:
			{
				DuelName = "S4S | Knife";
				PrimWep = "weapon_knife";
				PrimNum = CSWeapon_KNIFE;
			}
			
			case 11:
			{
				Weapons_MenuHandler(INVALID_HANDLE, MenuAction_Select, client, GetRandomInt(0, 9));
			}	
		}
		if(Type == 0)
		{
			HPamount = 100;
			BPAmmo = 0;
			Vest = 2;
			SecWep = "weapon_knife";
			SecNum = CSWeapon_KNIFE;
			ChooseRules(client);
		}
		else if(Type == 1)
		{
			ShowCustomMenu(client);
			if(PrimNum == CSWeapon_HEGRENADE)
				BPAmmo = 1;
			
			else
				BPAmmo = 10000;
		}
	}
	hMenu = INVALID_HANDLE;
}

public ShowCustomMenu(client)
{
	new String:TempFormat[100], String:WeaponName[50];
	
	new Handle:hMenu = CreateMenu(Custom_MenuHandler);

	Format(TempFormat, sizeof(TempFormat), "Health: %i", HPamount);
	AddMenuItem(hMenu, "", TempFormat);
	
	Format(WeaponName, sizeof(WeaponName), DuelName);
	ReplaceString(WeaponName, sizeof(WeaponName), "S4S | ", "");
	
	Format(TempFormat, sizeof(TempFormat), "Weapon: %s", WeaponName);
	AddMenuItem(hMenu, "", TempFormat);
	
	AddMenuItem(hMenu, "", "Random Health");
	
	AddMenuItem(hMenu, "", "Begin duel!");
	
	SetMenuTitle(hMenu, "[GlowX-LR] Custom Duel:");
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	CanSetHealth[client] = true;
}

public Custom_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		if(!LastRequest(client))
		{
			hMenu = INVALID_HANDLE;
			return;
		}
		switch(item+1)
		{
			case 1:
			{
				PrintToChat(client, "%s Please write in the chat the \x07amount \x01of health you want.", PREFIX);
		
					
				ShowCustomMenu(client);
			}
				
			case 2:
			{
				DuelName = "Custom | ";
				ShowWeaponMenu(client);
			}
			
			case 3:
			{
				HPamount = GetRandomInt(100, GetMaxHealthValue());
				ShowCustomMenu(client);	
			}
			case 4: 
			{
				ReplaceString(DuelName, sizeof(DuelName), "S4S | ", "Custom | ");
				
				Vest = 2;
				ChooseRules(client);
			}
		}
		
		if(item+1 != 1)
			CanSetHealth[client] = false;
	}
	hMenu = INVALID_HANDLE;
}


public ChooseRules(client)
{
		
	new Type; // S4S = 0, Custom = 1
	
	if(StrContains(DuelName, "S4S") != -1)
	{
		Type = 0;
	}
	else if(StrContains(DuelName, "Custom") != -1)
	{
		Type = 1;
	}

	new String:TempFormat[100];
	
	new Handle:hMenu = CreateMenu(Rules_MenuHandler);
	
	Format(TempFormat, sizeof(TempFormat), "%s: %sllowed", PrimNum == CSWeapon_KNIFE ? "Right Stab" : "Zoom", Zoom ? "A" : "Disa");
	AddMenuItem(hMenu, "", TempFormat);
	
	switch(Vest)
	{
		case 0: Format(TempFormat, sizeof(TempFormat), "Vest: Nothing");
		case 1: Format(TempFormat, sizeof(TempFormat), "Vest: Yes");
		default: Format(TempFormat, sizeof(TempFormat), "Vest: And Helmet");
	}
	AddMenuItem(hMenu, "", TempFormat);
	

	Format(TempFormat, sizeof(TempFormat), "%s: %s", PrimNum == CSWeapon_KNIFE ? "Backstab" : "Headshot", !HeadShot ? "Free" : "Only");
	AddMenuItem(hMenu, "", TempFormat);
	
	if(Type == 1)
	{
		Format(TempFormat, sizeof(TempFormat), "Jump: %sllowed", Jump ? "A" : "Disa");
		AddMenuItem(hMenu, "", TempFormat);
		
		Format(TempFormat, sizeof(TempFormat), "Duck: %sllowed", Duck ? "A" : "Disa");
		AddMenuItem(hMenu, "", TempFormat);
	}
	
	AddMenuItem(hMenu, "", "Random Rules");
	
	AddMenuItem(hMenu, "", "Select Opponent");
	
	SetMenuTitle(hMenu, "[GlowX-LR] Select battle rules:");
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Rules_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	new Type; // S4S = 0, Custom = 1
	
	if(StrContains(DuelName, "S4S") != -1)
	{
		Type = 0;
	}
	else if(StrContains(DuelName, "Custom") != -1)
	{
		Type = 1;
	}
	else
		Type = 2;
	
	if(action == MenuAction_Select)
	{
		if(!LastRequest(client))
			return;
		
		switch(item+1)
		{
			case 1:
			{
				Zoom = !Zoom;
				
				if(HPamount > GetMaxHealthValue())
				{	
					HPamount = GetMaxHealthValue();
					PrintToChat(client, "%s Duel \x07HP \x01was set to \x05%i \x01to avoid never ending duel.", PREFIX, HPamount);
				}	
			}
			case 2:
			{
				Vest++;
				
				if(Vest == 3)
					Vest = 0;
			}
			case 3:
			{
				HeadShot = !HeadShot;
				
				if(HPamount > GetMaxHealthValue())
				{	
					HPamount = GetMaxHealthValue();
					PrintToChat(client, "%s Duel \x07HP \x01was set to \x05%i to avoid never ending duel.", PREFIX, HPamount);
				}	
			}
			case 4:
			{
				if(Type == 0)
				{
					SetRandomRules(Type);
				}	
				else
				{
					Jump = !Jump;
				}
			}
			case 5:
			{
				if(Type == 0)
				{
					ChooseOpponent(client);
				}
				else
				{
					Duck = !Duck;
				}
			}
			case 6:
			{
				SetRandomRules(Type);
			}	
			case 7:	ChooseOpponent(client);
		}
		
		if( ( Type == 0 && item + 1 != 5 ) || ( Type == 1 && item + 1 != 7 ) ) ChooseRules(client); // This is to return to rules menu except when player decides to begin the duel.
		
	}

	hMenu = INVALID_HANDLE;
}
public ShowFunMenu(client)
{	
	new Handle:hMenu = CreateMenu(Fun_MenuHandler);
	
	AddMenuItem(hMenu, "", "Night Crawler ( Invisible )");
	AddMenuItem(hMenu, "", "Hide'N'Seek");
	AddMenuItem(hMenu, "", "Last Hit Bleeds");
	AddMenuItem(hMenu, "", "Super Deagle");
	AddMenuItem(hMenu, "", "Negev No Spread");
	AddMenuItem(hMenu, "", "Gun Toss");
	AddMenuItem(hMenu, "", "Dodgeball");
	AddMenuItem(hMenu, "", "Backstabs");
	//AddMenuItem(hMenu, "", "Ring of Death");
	
	//if(MapOkay)
		//AddMenuItem(hMenu, "", "Jump");
		
	AddMenuItem(hMenu, "", "Freeday");
	
	AddMenuItem(hMenu, "", "Random");
	
	SetMenuTitle(hMenu, "[GlowX-LR] Fun Duels:");
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Fun_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		if(!LastRequest(client))
		{
			hMenu = INVALID_HANDLE;
			return;
		}
		PrimWep = "";
		PrimNum = CSWeapon_NONE;
		SecWep = "";
		SecNum = CSWeapon_NONE;
		Vest = 0;
		Zoom = true;
		HeadShot = false;
		Jump = true;
		Duck = true;
		NoRecoil = false;
		
		switch(item + 1) 
		{
			case 1:
			{
				DuelName = "Fun | Night Crawler";
				PrimWep = "weapon_m4a1";
				PrimNum = CSWeapon_M4A1;
				SecWep = "weapon_knife";
				SecNum = CSWeapon_KNIFE;
				BPAmmo = 10000;
				HPamount = 100;
			}
			case 2:
			{
				DuelName = "Fun | HNS";
				SecWep = "weapon_knife";
				SecNum = CSWeapon_KNIFE;
			}
			case 3:
			{
				DuelName = "Fun | Last Hit Bleeds";
				SecWep = "weapon_knife";
				SecNum = CSWeapon_KNIFE;
				
				HPamount = 30000;
			}			
			case 4:
			{
				DuelName = "Fun | Super Deagle";
				HPamount = 500;
				BPAmmo = 10000;
				PrimWep = "weapon_deagle";
				PrimNum = CSWeapon_DEAGLE;
			}
			case 5:
			{
				DuelName = "Fun | Negev No Recoil";
				NoRecoil = true;
				HPamount = 1000;
				BPAmmo = 10000;
				PrimWep = "weapon_negev";
				PrimNum = CSWeapon_NEGEV;
			}
			case 6:
			{
				DuelName = "Fun | Gun Toss";
				HPamount = 100;
				PrimWep = "weapon_deagle";
				PrimNum = CSWeapon_DEAGLE;
				SecWep = "weapon_knife";
				SecNum = CSWeapon_KNIFE;
				BPAmmo = 0;
			}
			
			case 7:
			{
				DuelName = "Fun | Dodgeball";
				HPamount = 100;
				BPAmmo = 1;
				PrimWep = "weapon_decoy";
				PrimNum = CSWeapon_DECOY;
			}
			
			case 8:
			{
				DuelName = "Fun | Backstabs";
				HPamount = 100;
				Vest = 0;
				PrimWep = "weapon_knife"
				PrimNum = CSWeapon_KNIFE;
			}
			/*
			case 7:
			{
				DuelName = "Fun | Ring of Death";
				HPamount = 100;
				PrimWep = "weapon_knife";
				PrimNum = CSWeapon_KNIFE;
			}
			*/
			case 9: SetFreeday(client);
			
			case 10:
			{
				Fun_MenuHandler(INVALID_HANDLE, MenuAction_Select, client, GetRandomInt(0, 7));
			}
		}
		
		if(item+1 <= 2)
			ChooseSeeker(client); // Basicly reversing Guard and Prisoner.
	
		else if(item+1 < 9)
			ChooseOpponent(client);
		
	}
	
	hMenu = INVALID_HANDLE;
}

public ChooseSeeker(client)
{
	new Handle:hMenu = CreateMenu(Seeker_MenuHandler);

	AddMenuItem(hMenu, "", "You");
	
	AddMenuItem(hMenu, "", "Guard");
	
	AddMenuItem(hMenu, "", "Random");
	
	SetMenuTitle(hMenu, "[GlowX-LR] Choose who will seek:");
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Seeker_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	if(action == MenuAction_Select)
	{
		if(!LastRequest(client))
		{
			hMenu = INVALID_HANDLE;
			return;
		}
		if(item == 2)
			item = GetRandomInt(0, 1);
			
		TSeeker = item == 0 ? true : false;
		PrimNum = CSWeapon_NONE;
		SecNum = CSWeapon_NONE;
		HPamount = 100;
		BPAmmo = -1;
		
		ChooseOpponent(client);
	}

	hMenu = INVALID_HANDLE;
}

public ShowAutoMenu(client)
{
	new Handle:hMenu = CreateMenu(Auto_MenuHandler);

	AddMenuItem(hMenu, "", "First Writes");
	AddMenuItem(hMenu, "", "Combo Contest");
	AddMenuItem(hMenu, "", "Math Contest");
	AddMenuItem(hMenu, "", "Opposite Contest");
	AddMenuItem(hMenu, "", "Type Stages Contest");
	AddMenuItem(hMenu, "", "Most Jumps");
	//AddMenuItem(hMenu, "", "Spray");
	AddMenuItem(hMenu, "", "Random");
	
	SetMenuTitle(hMenu, "[GlowX-LR] Automatic Contests:");
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Auto_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	if(action == MenuAction_Select)
	{
		if(!LastRequest(client))
		{
			hMenu = INVALID_HANDLE;
			return;
		}
		EndLR(false);
		HPamount = GetMaxHealthValue();
		
		switch(item+1)
		{
			case 1: DuelName = "Auto | First Writes";
			
			case 2: DuelName = "Auto | Combo Contest";

			
			case 3: DuelName = "Auto | Math Contest";
			
			case 4: DuelName = "Auto | Opposite Contest";
			
			case 5: DuelName = "Auto | Type Stages Contest";
			
			case 6: DuelName = "Auto | Most Jumps";
			/*
			case 6:
			{
				DuelName = "Auto | Spray";
				PrimWep = "weapon_knife";
				PrimNum = CSWeapon_KNIFE;
			}
			*/
			case 7:
			{
				Auto_MenuHandler(INVALID_HANDLE, MenuAction_Select, client, GetRandomInt(0, 5));
			}
		}
			
		ChooseOpponent(client);
	}

	hMenu = INVALID_HANDLE;
}

public ChooseOpponent(client)
{	
	if(HPamount > GetMaxHealthValue())
	{
		HPamount = GetMaxHealthValue();
		PrintToChat(client, "%s Duel \x07HP \x01was set to \x05%i \x01to avoid never ending duel.", PREFIX, HPamount);
	}
	new String:UID[20], String:Name[64];
	new Handle:hMenu = CreateMenu(Opponent_MenuHandler);
	
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(!IsPlayerAlive(i))
			continue;
			
		else if(GetClientTeam(i) != CS_TEAM_CT)
			continue;
		
		IntToString(GetClientUserId(i), UID, sizeof(UID));
		GetClientName(i, Name, sizeof(Name));
		AddMenuItem(hMenu, UID, Name);
	}
	
	SetMenuTitle(hMenu, "[GlowX-LR] Select a Guard to battle against.");
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public Opponent_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	if(action == MenuAction_Select)
	{
		if(!LastRequest(client))
		{
			hMenu = INVALID_HANDLE;
			return;
		}
		new String:UID[20], String:Display[1], style;
		GetMenuItem(hMenu, item, UID, sizeof(UID), style, Display, sizeof(Display));
		
		new target = GetClientOfUserId(StringToInt(UID));
		
		if(LastRequest(client) && target != 0)
		{
			Guard = target;			
			
			Prisoner = client;
			LRStarted = true;
			//OpenAllCells();
			FinishTimers();
			StartDuel();
			
			PrintToChatAll("%s \x01%s \x07%N \x01vs \x07%N ", PREFIX, DuelName, Prisoner, Guard);
			
		}
		else ChooseOpponent(client);
	}
	
	hMenu = INVALID_HANDLE;
}

public OpenAllCells()
{

	new ent = -1;
	
	while((ent = FindEntityByClassname(ent, "func_button")) != INVALID_ENT_REFERENCE)
		AcceptEntityInput(ent, "Press");
}


public StartRambo()
{
	Rambo = true;
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(!IsPlayerAlive(i))
			continue;
			
		else if(GetClientTeam(i) != CS_TEAM_CT)
			continue;
			
		StripPlayerWeapons(i);
		SetEntityHealth(i, 100);
		SetClientArmor(i, Vest == 0 ? 0 : 100, Vest == 2 ? 1 : 0);
		new weapon = GivePlayerItem(i, "weapon_m4a1");
		SetClientAmmo(i, weapon, 999);
	}
	
	StripPlayerWeapons(Prisoner);
	new weapon = GivePlayerItem(Prisoner, "weapon_negev");
						
	SetClientAmmo(Prisoner, weapon, 999);
	SetEntityHealth(Prisoner, 250);
						
	SetClientArmor(Prisoner, Vest == 0 ? 0 : 100, Vest == 2 ? 1 : 0);
	
	TIMER_INFOMSG = CreateTimer(0.1, ShowToAll, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	TIMER_SLAYALL = CreateTimer(420.0, SlayAllParts, _, TIMER_FLAG_NO_MAPCHANGE);

	PrintToChatAll("%s All \x05participants \x01will be slayed in \x077 \x01minutes!", PREFIX);
}

public StartDuel()
{	
	for(new i=1;i <= MaxClients;i++)
	{
		ShowMessage[i] = true;
	}
	new ent = -1;
	
	while((ent = FindEntityByClassname(ent, "game_player_equip")) != -1)
		AcceptEntityInput(ent, "Kill");
		
	while((ent = FindEntityByClassname(ent, "player_weaponstrip")) != -1)
		AcceptEntityInput(ent, "Kill");

	AllowGunTossPickup = true;
	SetClientGodmode(Guard);
	SetClientNoclip(Guard);
	
	SetClientSpeed(Guard);
	SetClientSpeed(Prisoner);
	
	StripPlayerWeapons(Guard);
	StripPlayerWeapons(Prisoner);
	
	SetEntityHealth(Guard, HPamount);
	SetEntityHealth(Prisoner, HPamount);
	
	SetEntityMaxHealth(Guard, HPamount);
	SetEntityMaxHealth(Prisoner, HPamount);
	
	SetClientArmor(Guard, Vest == 0 ? 0 : 100, Vest == 2 ? 1 : 0);
	SetClientArmor(Prisoner, Vest == 0 ? 0 : 100, Vest == 2 ? 1 : 0);
	
	if(PrimNum != CSWeapon_NONE) // ID 0 is also invalid.
	{
		do // Don't fookin ask how I get these bugs, I just do
		{
			GuardPrim = GivePlayerItem(Guard, PrimWep);
		}
		while(GuardPrim == -1)
		
		do
		{
			PrisonerPrim = GivePlayerItem(Prisoner, PrimWep);
		}
		while(PrisonerPrim == -1)

		if(PrimNum != CSWeapon_KNIFE && PrimNum != CSWeapon_C4)
		{
				SetClientAmmo(Guard, GuardPrim, BPAmmo);
				SetClientAmmo(Prisoner, PrisonerPrim, BPAmmo);
		}
		
	}
	if(SecNum != CSWeapon_NONE)
	{
		GuardSec = GivePlayerItem(Guard, SecWep);
		PrisonerSec = GivePlayerItem(Prisoner, SecWep);
		if(SecNum != CSWeapon_KNIFE && SecNum != CSWeapon_C4)
		{
			SetClientAmmo(Guard, GuardSec, BPAmmo);
			SetClientAmmo(Prisoner, PrisonerSec, BPAmmo);
		}
	}
	
	ContinueStartDuel(); // To make things more organized :)
}

public ContinueStartDuel()
{	
	SetEntityGlow(Guard, true, 128, 0, 128);
	SetEntityGlow(Prisoner, true, 128, 0, 128);
	
	
	if(StrContains(DuelName, "S4S") != -1)
	{
		RequestFrame(ResetClipAndFrame, 0);
		
		PlaySoundToAll(LR_SOUNDS_BACKSTAB);
	}
	
	else if(StrContains(DuelName, "Dodgeball") != -1)
	{
		Dodgeball = true;
		
		SetEntProp(Guard, Prop_Data, "m_CollisionGroup", 5);
		SetEntProp(Prisoner, Prop_Data, "m_CollisionGroup", 5);
	}	
	
	else if(StrContains(DuelName, "HNS") != -1) // If the duel is HNS.
	{
		if(!TSeeker) // If the terrorist doesn't seek.
		{
			new Guard2 = Guard;
			new Prisoner2 = Prisoner;
			
			Prisoner = Guard2;
			Guard = Prisoner2;
		}
		
		GivePlayerItem(Prisoner, "weapon_knife");
		StripPlayerWeapons(Guard);
		
		SetEntityHealth(Guard, 100);
		SetEntityHealth(Prisoner, 100);
		
		Timer = 60;
		TIMER_COUNTDOWN = CreateTimer(1.0, ShowTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	else if(StrContains(DuelName, "Bleed") != -1)
	{
		Bleed = true;
		
		BleedTarget = 0;
		
		PrintToChatAll("Last Hit Bleed has started. You must not be the last stabbed");
		
		TIMER_COUNTDOWN = CreateTimer(1.0, BleedTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
		TriggerTimer(TIMER_COUNTDOWN, true);
	}
	else if(StrContains(DuelName, "Night Crawler") != -1)
	{
		if(!TSeeker) // If the terrorist doesn't seek.
		{
			new Guard2 = Guard;
			new Prisoner2 = Prisoner;
			
			Prisoner = Guard2;
			Guard = Prisoner2;
		}
		
		StripPlayerWeapons(Prisoner);
		GivePlayerItem(Prisoner, "weapon_knife");
		
		new weapon = GivePlayerItem(Guard, "weapon_m4a1");
		SetClientAmmo(Guard, weapon, 10000);
		
		Timer = 60;
		TIMER_COUNTDOWN = CreateTimer(1.0, ShowTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	else if(StrContains(DuelName, "Shark") != -1)
	{
		if(!TSeeker) // If the terrorist doesn't seek.
		{
			new Guard2 = Guard;
			new Prisoner2 = Prisoner;
			
			Prisoner = Guard2;
			Guard = Prisoner2;
		}
		
		GivePlayerItem(Prisoner, "weapon_knife");
		SetEntityHealth(Prisoner, 200);
		SetClientNoclip(Prisoner, true);
		
		new weapon = GivePlayerItem(Guard, "weapon_m4a1");
		SetClientAmmo(Guard, weapon, 10000);
		
		Timer = 60;
		
		SetConVarFloat(hcv_NoclipSpeed, 1.3);
		TIMER_COUNTDOWN = CreateTimer(1.0, ShowTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	else if(StrContains(DuelName, "Backstabs") != -1)
	{
		HeadShot = true;
		
		PlaySoundToAll(LR_SOUNDS_BACKSTAB);
		
		PrintToChatAll("%s \x07Stab! Stab! Stab! ", PREFIX);
		PrintToChatAll("%s \x07Stab! Stab! Stab! ", PREFIX);
		PrintToChatAll("%s \x07Stab! Stab! Stab! ", PREFIX);
		PrintToChatAll("%s \x07Stab! Stab! Stab! ", PREFIX);
	}
	
	else if(StrContains(DuelName, "Gun Toss") != -1)
	{
		SetWeaponClip(GuardPrim, 0);
		SetWeaponClip(PrisonerPrim, 0);
		
		LastDistance[Prisoner] = 0.0;
		LastDistance[Guard] = 0.0;
		
		GunToss = true;
		
		BPAmmo = 0;
		
		DroppedDeagle[Prisoner] = false;
		DroppedDeagle[Guard] = false;
		
		TIMER_100MILISECONDS = CreateTimer(0.1, DisallowGunTossPickup, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	else if(StrContains(DuelName, "Shoot The Bomb") != -1)
	{
		PrisonerSec = GivePlayerItem(Prisoner, "weapon_c4");
		GuardSec = GivePlayerItem(Guard, "weapon_c4");
	}
	
	else if(StrContains(DuelName, "First Writes") != -1)
	{
		StripPlayerWeapons(Prisoner);
		StripPlayerWeapons(Guard);
		
		firstwrites = true;
		firstcountdown = 5;
		TIMER_REACTION = CreateTimer(1.0, FirstWritesCountDown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
	}
	
	else if(StrContains(DuelName, "Combo Contest") != -1)
	{
		StripPlayerWeapons(Prisoner);
		StripPlayerWeapons(Guard);
		
		combo_started = true;
		combocountdown = 5;
		TIMER_REACTION = CreateTimer(1.0, ComboContestCountDown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
	}
	
	else if(StrContains(DuelName, "Math Contest") != -1)
	{
		StripPlayerWeapons(Prisoner);
		StripPlayerWeapons(Guard);
		
		mathcontest = true;
		mathcontestcountdown = 5;
		TIMER_REACTION = CreateTimer(1.0, MathContestCountDown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
	}

	else if(StrContains(DuelName, "Opposite Contest") != -1)
	{
		StripPlayerWeapons(Prisoner);
		StripPlayerWeapons(Guard);
		
		opposite = true;
		oppositecountdown = 5;
		TIMER_REACTION = CreateTimer(1.0, OppositeContestCountDown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
	}
	
	else if(StrContains(DuelName, "Type Stages") != -1)
	{
		StripPlayerWeapons(Prisoner);
		StripPlayerWeapons(Guard);
		
		typestages = true;
		typestagescountdown = 5;
		TIMER_REACTION = CreateTimer(1.0, TypeStagesCountDown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
	}
	/*
	else if(StrContains(DuelName, "Spray") != -1)
	{
		SetEntPropFloat(Prisoner, Prop_Send, "m_flNextDecalTime", 0.0);
		SetEntPropFloat(Guard, Prop_Send, "m_flNextDecalTime", 0.0);
		PrintToChatAll("Each player can spray once ONLY!");
		PrintToChatAll("You can only use E to spray, once you press it will spray it for you.");
	}
	
	else if(StrContains(DuelName, "Ring") != -1)
	{
		Ring = true;
		
		GetClientAbsOrigin(Prisoner, RingOrigin);

		new Float:GuardOrigin[3];
		
		GuardOrigin = RingOrigin;

		//GuardOrigin[2] += 85.0;
		
		RingOrigin[2] += 30.0;
		
		TeleportEntity(Guard, GuardOrigin, NULL_VECTOR, Float:{0.0, 0.0, -0.1});
		
		PrintToChatAll("%s \x01Use right click to push your \x07opponent!", PREFIX);
		PrintToChatAll("%s \x01Use right click to push your \x07opponent!", PREFIX);
		PrintToChatAll("%s \x01Use right click to push your \x07opponent!", PREFIX);

		new Float:Sensitivity = 1.0;
		
		new bool:NoRing = false;
		new Float:Position[3], Float:Angles[3];
		
		Angles = Float:{0.0, 0.0, 0.0};
		
		GetClientEyePosition(Prisoner, Position); 
		
		for(new Float:i=0.0;i <= 360.0;i += Sensitivity)
		{
			Angles[1] = i;
			
			TR_TraceRayFilter(Position, Angles, MASK_PLAYERSOLID, RayType_Infinite, Trace_DontHitPlayers); //Start the trace 
			
			new Float:EndPosition[3];
			
			TR_GetEndPosition(EndPosition);
			
			EndPosition[2] = 0.0;
			Position[2] = 0.0;
			
			new Float:DistanceSquared = GetVectorDistance(Position, EndPosition, true);
			
			if(DistanceSquared <= FloatSquare(BeamRadius - BeamWidth + 20.0))
			{
				NoRing = true;
			}
		}
		
		if(NoRing)
			PrintToChatEyal("Error: Could not locate a good ring point.");
			
		CreateTimer(0.1, SetUpRing, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	*/
	if(StrContains(DuelName, "Most Jumps") != -1)
	{
		StripPlayerWeapons(Guard);
		StripPlayerWeapons(Prisoner);
		
		MostJumps = true;
		
		TIMER_MOSTJUMPS = CreateTimer(20.0, EndMostJumps, _, TIMER_FLAG_NO_MAPCHANGE);
		
		mostjumpscountdown = 5;
		TIMER_REACTION = CreateTimer(1.0, MostJumpsCountDown, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		
		PrintToChatAll("%s All players have \x0715 \x01seconds to jump as much as they can!", PREFIX);
		
		
	}	
	else if(StrContains(DuelName, "Auto") != -1)
	{
		new Float:Time = 20.0;

		if(StrContains(DuelName, "Type Stages") != -1)
			Time += 40.0;
			
		if(StrContains(DuelName, "Math") != -1)
			Time += 20.0;
			
		TIMER_FAILREACTION = CreateTimer(Time, FailReaction, _, TIMER_FLAG_NO_MAPCHANGE);
		
		PrintToChatAll("%s A random \x05participant \x01will be killed in \x07%i \x01seconds!", PREFIX, RoundFloat(Time));
	}
	else
	{
		TIMER_SLAYALL = CreateTimer(300.0, SlayAllParts, _, TIMER_FLAG_NO_MAPCHANGE);
	
		PrintToChatAll("%s All \x05participants \x01will be slayed in \x075 \x01minutes!", PREFIX);
	}
	new bool:NC;
	
	NC = StrContains(DuelName, "Night Crawler") != -1 ? true : false;
	TIMER_INFOMSG = CreateTimer(0.1, ShowToAll, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	
	if(StrContains(DuelName, "HNS") == -1)
	{
		TIMER_BEACON[Prisoner] = CreateTimer(NC ? 7.5 : 1.0, BeaconPlayer, Prisoner, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		TIMER_BEACON[Guard] = CreateTimer(1.0, BeaconPlayer, Guard, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	new nullint;
	Call_StartForward(fw_LRStarted);
	
	Call_PushCell(Prisoner);
	Call_PushCell(Guard);
	
	Call_Finish(nullint);
	//set_task(NC ? 7.5 : 1.0, "Beacon", BEACON_TASKID);
	
	//Teleport();
}

public DeleteAllGuns()
{
	if(!LRStarted)
		return;
		
	new String:Classname[50];
	new entCount = GetEntityCount();
	for(new i=MaxClients+1;i < entCount;i++)
	{
		if(!IsValidEntity(i))
			continue;
			
		else if(!IsValidEdict(i))
			continue;
		
		GetEdictClassname(i, Classname, sizeof(Classname));
		
		if(StrContains(Classname, "weapon_", true) == -1)
			continue;
			
		new owner = GetEntityOwner(i);
		
		if(owner != -1)
			continue;
		
		AcceptEntityInput(i, "Kill");
	}
}

public Action:DisallowGunTossPickup(Handle:hTimer)
{
	DeleteAllGuns();
	
	AllowGunTossPickup = false;	
	
	TIMER_100MILISECONDS = INVALID_HANDLE;
}
public Action:BeaconPlayer(Handle:hTimer, client) // It is guaranteed that no way another player will be used instead of the client, no need for user id.
{
	if(!LRPart(client))
		return Plugin_Stop;
		
	else if(!IsPlayerAlive(client))
		return Plugin_Stop;
	
	new Float:vec[3];
	GetClientAbsOrigin(client, vec);
	vec[2] += 10;
        
	new rgba[4] = {255, 255, 255, 255};
	
	for(new i=0;i < 3;i++)
	{
		rgba[i] = GetRandomInt(0, 255);
	}
	
	TE_SetupBeamRingPoint(vec, 10.0, 375.0, g_BeamSprite, g_HaloSprite, 0, 10, 0.6, 10.0, 0.5, rgba, 10, 0);
        
	TE_SendToAll();
        
	GetClientEyePosition(client, vec);
	//EmitAmbientSound(SOUND_BLIP, vec, client, SNDLEVEL_RAIDSIREN);

	return Plugin_Continue;
	
}

public Action:SlayAllParts(Handle:hTimer)
{
	if(!LRStarted)
		return Plugin_Stop;
	
	new Pris = Prisoner; // Slaying the Guard will wipe out the prisoner's integer
	new Guar = Guard;
	
	EndLR();
	
	if(Guar != -1)
		ForcePlayerSuicide(Guar);
		
	if(Pris != -1)
		ForcePlayerSuicide(Pris);
		
	PrintToChatAll("%s All \x07LR \x01Participants were slayed for taking too long.", PREFIX);
	TIMER_SLAYALL = INVALID_HANDLE;
	
	return Plugin_Stop;
}

public Action:SetUpRing(Handle:hTimer)
{
	if(!LRStarted)
		return Plugin_Stop;


	
	new Float:TempRingOrigin[3];
	
	TempRingOrigin = RingOrigin;
	
	TempRingOrigin[2] -= 30.0;
	for(new i=0;i < 5;i++) // 
	{
		TE_SetupBeamRingPoint(TempRingOrigin, BeamRadius-BeamWidth, BeamRadius, RingBeamModel, RingHaloModel, 0, 10, 0.6, 10.0, 0.5, {255, 255, 255, 255}, 1, 0);
		TE_SendToAll();
		TempRingOrigin[2] += 30.0;
	}
	
	new Float:PrisonerOrigin[3], Float:GuardOrigin[3];
	
	GetEntPropVector(Prisoner, Prop_Data, "m_vecOrigin", PrisonerOrigin);
	GetEntPropVector(Guard, Prop_Data, "m_vecOrigin", GuardOrigin);
	
	GuardOrigin[2] = RingOrigin[2];
	PrisonerOrigin[2] = RingOrigin[2];
	
	if(GetVectorDistance(PrisonerOrigin, RingOrigin, false) > BeamRadius / 2 + BeamWidth)
	{
		Ring = false; // To block any damage immunity
		FinishHim(Prisoner, Guard);
	}
	else if(GetVectorDistance(GuardOrigin, RingOrigin, false) > BeamRadius / 2 + BeamWidth)
	{
		Ring = false; // To block any damage immunity
		FinishHim(Guard, Prisoner);
	}
	
	return Plugin_Continue;
	
	
}

public Action:FailReaction(Handle:hTimer)
{
	new target = Guard; // Killer
	if(GetRandomInt(0, 1) == 1) target = Prisoner;
	
	//if(!StrEquali(DuelName, "Auto | Spray"))
	FinishHim(target == Guard ? Prisoner : Guard, target);
	/*
	else
	{
		if(GuardSprayHeight == 0.0 && PrisonerSprayHeight == 0.0)
			target = target * 1;
		
		else if(GuardSprayHeight == 0.0 && PrisonerSprayHeight != 0.0)
			target = Prisoner;
			
		else if(GuardSprayHeight != 0.0 && PrisonerSprayHeight == 0.0)
			target = Guard;
			
		else
		{
			PrintToChatAll("Last Request error occured. Tell to Eyal282 ASAP please.");
			SetFailState("Last request error");
		}
		FinishHim(target == Guard ? Prisoner : Guard, target);
	}	
	*/
	PrintToChatAll("%s Duel time has \x07expired! \x01Winner is \x05%N!", PREFIX, target);
	
	TIMER_FAILREACTION = INVALID_HANDLE;
}

public Action:EndMostJumps(Handle:hTimer)
{
	if(GuardJumps > PrisonerJumps)
	{
		PrintToChatAll("%s \x05%N \x01won the duel!", PREFIX, Guard);
		PrintToChatAll("%s \x05%N \x01had \x07%i \x01jumps while \x05%N \x01had \x05%i \x01jumps", PREFIX, Guard, GuardJumps, Prisoner, PrisonerJumps);
		FinishHim(Prisoner, Guard);
	}
	else if(PrisonerJumps > GuardJumps)
	{
		PrintToChatAll("%s \x05%N \x01won the duel!", PREFIX, Prisoner);
		PrintToChatAll("%s \x05%N \x01had \x05%i \x01jumps while \x05%N \x01had \x05%i \x01jumps", PREFIX, Prisoner, PrisonerJumps, Guard, GuardJumps);
		FinishHim(Guard, Prisoner);
	}
	else
	{
		new winner, jumps, loser;
		
		if(GetRandomInt(0, 1) == 0)
		{
			winner = Guard;
			loser = Prisoner;
		}
		else
		{
			winner = Prisoner;
			loser = Guard;			
		}
		
		jumps = PrisonerJumps;
		PrintToChatAll("%s \x05%N \x01randomly won the duel!", PREFIX, winner);
		PrintToChatAll("%s \x01Both players had \x05%i \x01jumps!", PREFIX, jumps);
		FinishHim(loser, winner);
	}
	
	TIMER_MOSTJUMPS = INVALID_HANDLE;
}
/*
public Action:OnCustomSpray_Post(client, Float:HeightFromGround, Cheater)
{
	if(!LRStarted)
		return Plugin_Continue;
	
	else if(!LRPart(client))
		return Plugin_Continue;
		
	else if(StrContains(DuelName, "Spray") == -1)
		return Plugin_Continue;
		
	if(Prisoner == client)
		PrisonerSprayHeight = HeightFromGround;
		
	else
		GuardSprayHeight = HeightFromGround;
		
	if(GuardSprayHeight != 0.0 && PrisonerSprayHeight != 0.0)
	{
	
		if(GuardSprayHeight > PrisonerSprayHeight)
		{	
			PrintToChatAll("\x01Guard\x03 %N\x01 wins the duel!", Guard);
			
			FinishHim(Prisoner, Guard);
		}
			
		else if(PrisonerSprayHeight > GuardSprayHeight)
		{
			
			PrintToChatAll("\x01Prisoner\x03 %N\x01 wins the duel!", Prisoner);
			
			FinishHim(Guard, Prisoner);
		}
		
		else
		{
			SetEntPropFloat(Guard, Prop_Send, "m_flNextDecalTime", 0.0);
			SetEntPropFloat(Prisoner, Prop_Send, "m_flNextDecalTime", 0.0);
			PrintToChatAll("\x01Spray heights are identical! Resetting spray timer for all players!");
		}
		
		GuardSprayHeight = 0.0;
		PrisonerSprayHeight = 0.0;
	}
	return Plugin_Continue;
}
*/
/*
public Teleport()
{
	new ReadFile[100], Token[3][200], TOrigin[200], CTOrigin[200], Duel[200], Line, Length;
	
	new DuelNameNeeded[50];

	formatex(DuelNameNeeded, sizeof(DuelNameNeeded), DuelName);
	
	if(equali(DuelName, "S4S", 3))
		formatex(DuelNameNeeded, sizeof(DuelNameNeeded), "S4S");

	while(read_file(TPDir, Line++, ReadFile, sizeof(ReadFile), Length))
	{
		if(!read_file(TPDir, Line, ReadFile, sizeof(ReadFile), Length))
		{
			break;
		}

		if(ReadFile[0] == ';' || strcmp(ReadFile, "") == 0) continue;
		
		strtok(ReadFile, TOrigin, 199, Token[0], 199, '=');
		strtok(Token[0], CTOrigin, 199, Duel, 199, '=');
		
		remove_quotes(Duel);
		if(strcmp(Duel, DuelNameNeeded) != 0) continue;
		
		new Origin[3];
			
		parse(TOrigin, Token[0], 199, Token[1], 199, Token[2], 199);
		
		for(new i;i < 3;i++)
			remove_quotes(Token[i]);
			
		Origin[0] = str_to_num(Token[0]);
		Origin[1] = str_to_num(Token[1]);
		Origin[2] = str_to_num(Token[2]);
		
		set_user_origin(Prisoner, Origin);
		
		Origin[2] += 100;

		parse(CTOrigin, Token[0], 199, Token[1], 199, Token[2], 199);
		
		for(new i;i < 3;i++)
			remove_quotes(Token[i]);
			
		Origin[0] = str_to_num(Token[0]);
		Origin[1] = str_to_num(Token[1]);
		Origin[2] = str_to_num(Token[2]);
		
		set_user_origin(Guard, Origin);
		
		Origin[2] += 100;
	}
}
*/
public Action:ComboContestCountDown(Handle:hTimer)
{
	if(combo_started) 
	{
		if(combocountdown == 0)
		{
			ComboMoveAble();
			
			TIMER_REACTION = INVALID_HANDLE;
			return Plugin_Stop;
		}	
		else if(combocountdown > 0)
		{
			SetHudMessage(-1.0, 0.35, 0.9, 0, 50, 255);
			ShowHudMessage(0, HUD_REACTION, "Combo contest will start in\n%i Second%s\n", combocountdown, combocountdown > 1 ? "s" : "");
			combocountdown--;
		}
	}
	
	return Plugin_Continue;
}

public ComboMoveAble() 
{ 
	if(!LRStarted || !combo_started)
		return; 
	
	maxbuttons = 10;
	
	new iNumbers[ 12 ];
	for( new i; i < sizeof( iNumbers )-1; i++ )
	{
		iNumbers[ i ] = i;
	}
	
	SortCustom1D( iNumbers, 11, fnSortFunc ); 
	
	for( new i; i < maxbuttons; i++ )
	{
		if( i > 0 )
		{
			if( iNumbers[ i ] == g_combo[ i-1 ] ) 
			{
				continue;
			}
		}
		g_combo[ i ] = iNumbers[ i ];
	}

	
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		g_count[ i ] = 0; 
	}
	
	g_buttons[ 0 ] = IN_ATTACK; 
	g_buttons[ 1 ] = IN_JUMP; 
	g_buttons[ 2 ] = IN_DUCK; 
	g_buttons[ 3 ] = IN_FORWARD; 
	g_buttons[ 4 ] = IN_BACK; 
	g_buttons[ 5 ] = IN_USE; 
	g_buttons[ 6 ] = IN_MOVELEFT; 
	g_buttons[ 7 ] = IN_MOVERIGHT; 
	g_buttons[ 8 ] = IN_ATTACK2; 
	g_buttons[ 9 ] = IN_RELOAD;
	g_buttons[ 10 ] = IN_SCORE;
	
	combomoveable = true;
} 


public fnSortFunc( elem1, elem2, const array[], Handle:hndl )  
{ 
	new iNum = GetRandomInt( 0, 60 );
	
	if( iNum < 30 )
	{
		return -1;
	}
	else if( iNum == 30 )
	{
		return 0;
	}
	
	return 1;
} 

public Event_Think(client)
{
	if(!LRStarted)
		return;
	
	else if(!LRPart(client))
		return;
	
	if(NoRecoil)
	{
		new ActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	
		if(IsValidEdict(ActiveWeapon) && ActiveWeapon != -1) 
		{
			SetEntPropFloat(ActiveWeapon, Prop_Send, "m_fAccuracyPenalty", 0.0);
		}
		SetEntPropVector(client, Prop_Send, "m_aimPunchAngle", NULL_VECTOR);
		SetEntPropVector(client, Prop_Send, "m_aimPunchAngleVel", NULL_VECTOR);
		SetEntPropVector(client, Prop_Send, "m_viewPunchAngle", NULL_VECTOR);
	}
}
public Event_PlayerPreThink(client) 
{ 
	if(!LRStarted)
		return;
	
	else if(!LRPart(client))
		return;
	
	if(NoRecoil)
	{
		new ActiveWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	
		if(IsValidEdict(ActiveWeapon) && ActiveWeapon != -1) 
		{
			SetEntPropFloat(ActiveWeapon, Prop_Send, "m_fAccuracyPenalty", 0.0);
			
		}
		
		SendConVarValue(client, hcv_NoSpread, "1");
		
		SetEntPropVector(client, Prop_Send, "m_aimPunchAngle", NULL_VECTOR);
		SetEntPropVector(client, Prop_Send, "m_aimPunchAngleVel", NULL_VECTOR);
		SetEntPropVector(client, Prop_Send, "m_viewPunchAngle", NULL_VECTOR);
	}
	
	else if(GunToss)
	{		
		if(GetEntityFlags(client) & FL_ONGROUND && !DroppedDeagle[client])
		{
			GetEntPropVector(client, Prop_Data, "m_vecOrigin", JumpOrigin[client]);
			if(FloatAbs(GetGroundHeight(client) - GroundHeight[client]) <= 25.0)
				GroundHeight[client] = GetGroundHeight(client);
				
			AdjustedJump[client] = false; // This is to prevent resetting if it HAPPENS to be that the player jumps off a place, reaches air below 50 units and returns to it or something.
		}
		else 
		{
			if(FloatAbs(GetGroundHeight(client) - GroundHeight[client]) <= 25.0 && !AdjustedJump[client])
			{
				new Float:Origin[3];
				GetEntPropVector(client, Prop_Data, "m_vecOrigin", Origin);
				
				JumpOrigin[client][0] = Origin[0];
				JumpOrigin[client][1] = Origin[1];
				GroundHeight[client] = GetGroundHeight(client);
			}
			else 
			{
				AdjustedJump[client] = true;
			}
		}
		
	}
	
	if(!combo_started || !combomoveable)
		return;
		
	
	new iButton;
	iButton = GetClientButtons(client);
	
	if( g_count[ client ] >= maxbuttons )
	{ 
		combo_started = false;
		combomoveable = false;
		
		FinishHim(Prisoner == client ? Guard : Prisoner, client);
		
		g_count[ client ] = 0 ;
	} 
	
	if( g_count[ client ] != 0 )
	{
		if( iButton & g_buttons[ g_combo[ g_count[ client ]-1 ] ] )
		{
			return;
		}
	}
	
	if( iButton & g_buttons[ g_combo[ g_count[ client ] ] ] )
	{
		g_count[ client ] ++;
	}
	else if( iButton )
	{
		g_count[ client ] = 0;
	}
	
	showcombo( client );
}

showcombo( client )
{
	SetHudMessage(-1.0, 0.2, 1.0, 0, 50, 255);
	
	new String:name[ 11 ][ 33 ];
	
	for( new i; i<maxbuttons; i++ )
	{
		Format( name[ i ], 32, names[ g_combo[ i ] ] );
		if( i == g_count[ client ] )
		{
			Format( name[ i ], 32, names[ g_combo[ i ] +11 ] );
		}
	}

	switch( maxbuttons )
	{
		case 5:  ShowHudMessage( client, HUD_REACTION, css[ maxbuttons ], name[ 0 ], name[ 1 ], name[ 2 ], name[ 3 ], name[ 4 ] );
		case 6:  ShowHudMessage( client, HUD_REACTION, css[ maxbuttons ], name[ 0 ], name[ 1 ], name[ 2 ], name[ 3 ], name[ 4 ], name[ 5 ] );
		case 7:  ShowHudMessage( client, HUD_REACTION, css[ maxbuttons ], name[ 0 ], name[ 1 ], name[ 2 ], name[ 3 ], name[ 4 ], name[ 5 ], name[ 6 ] );
		case 8:  ShowHudMessage( client, HUD_REACTION, css[ maxbuttons ], name[ 0 ], name[ 1 ], name[ 2 ], name[ 3 ], name[ 4 ], name[ 5 ], name[ 6 ], name[ 7 ] );
		case 9:  ShowHudMessage( client, HUD_REACTION, css[ maxbuttons ], name[ 0 ], name[ 1 ], name[ 2 ], name[ 3 ], name[ 4 ], name[ 5 ], name[ 6 ], name[ 7 ], name[ 8 ] ); 
		case 10: ShowHudMessage( client, HUD_REACTION, css[ maxbuttons ], name[ 0 ], name[ 1 ], name[ 2 ], name[ 3 ], name[ 4 ], name[ 5 ], name[ 6 ], name[ 7 ], name[ 8 ], name[ 9 ] );
	}
}


public Action:FirstWritesCountDown(Handle:hTimer)
{
	new String:Number[21];
	IntToString(firstcountdown, Number, sizeof(Number));
	
	if(firstwrites) 
	{
		if(firstcountdown == 0) 
		{
			Format(firstchars, GetRandomInt(5, sizeof(firstchars)), "%i%i%i%i%i%i%i%i", GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9));
				
			firstwritesmoveable = true;
			
			TIMER_REACTION = INVALID_HANDLE;
			
			return Plugin_Stop;
		} 
		else if(firstcountdown > 0) 
		{	
			SetHudMessage(-1.0, 0.35, 0.9, 0, 50, 255);
			ShowHudMessage(0, HUD_REACTION, "First Writes contest will start in\n %i Second%s", firstcountdown, firstcountdown > 1 ? "s" : "");
			firstcountdown--;
		}
	}
	
	return Plugin_Continue;
}
/*
public FirstListenCountDown()
{
	new Args[2][21];
	
	if(firstlisten) 
	{
		if(firstlistencountdown == 0) 
		{
			firstlistennum = GetRandomInt(1, 99);
			firstlistenmoveable = true;
			
			num_to_str(firstlistennum, Args[0], 20);
			num_to_word(firstlistennum, Args[1], 20);
			
			client_cmd(0, "spk ^"vox/%s^"", Args[1]);
		}
		else if(firstlistencountdown > 0) 
		{
			client_cmd(0, "spk ^"fvox/bell^"");
			set_hudmessage(0, 50, 255, -1.0, 0.35, 0, 6.0, 0.9, 0.1, 0.2, 6);
			show_hudmessage(0, "First listen contest will start in\n %i Second%s\n", firstlistencountdown, firstlistencountdown > 1 ? "s" : "");
			firstlistencountdown--;
			set_task(1.0, "FirstListenCountDown");
		}
	}
}
*/
public Action:MathContestCountDown(Handle:hTimer)
{
	if(mathcontest) 
	{
		if(mathcontestcountdown == 0) 
		{
			mathplus = GetRandomInt(0, 1) == 1 ? true : false;
			mathnum[1] = GetRandomInt(100, 1000);
			mathnum[0] = GetRandomInt(mathplus == true ? 100 : mathnum[1], mathplus == true ? 1000 : 1500); // This is to prevent a case of nagative numbers, which are my sworn enemies.
			
			Format(mathresult, sizeof(mathresult), "%i", mathplus == true ? mathnum[0] + mathnum[1] : mathnum[0] - mathnum[1]);
			mathcontestmoveable = true;
			TIMER_REACTION = INVALID_HANDLE;
			
			return Plugin_Stop;
		} 
		else if(mathcontestcountdown > 0) 
		{
			SetHudMessage(-1.0, 0.35, 0.9, 0, 50, 255);
			ShowHudMessage(0, HUD_REACTION, "Math contest will start in\n%i Second%s\n", mathcontestcountdown, mathcontestcountdown > 1 ? "s" : "");
			mathcontestcountdown--;
		}
	}
	
	return Plugin_Continue;
}

public Action:OppositeContestCountDown(Handle:hTimer)
{	
	if(opposite) 
	{
		if(oppositecountdown == 0)
		{
			oppositewords = GetRandomInt(0, sizeof(OppositeWords1) - 1);
			oppositemoveable = true;
			TIMER_REACTION = INVALID_HANDLE;
			
			return Plugin_Stop;
		} 
		else if(oppositecountdown > 0)
		{
			SetHudMessage(-1.0, 0.35, 0.9, 0, 50, 255);
			ShowHudMessage(0, HUD_REACTION, "Opposite contest will start in\n%i Second%s\n", oppositecountdown, oppositecountdown > 1 ? "s" : "");
			oppositecountdown--;
		}
	}

	return Plugin_Continue;
}

public Action:TypeStagesCountDown(Handle:hTimer)
{	
	if(typestages) 
	{
		if(typestagescountdown == 0) 
		{	
			typestagesmaxstages = GetRandomInt(5, 10);
			for(new i=0;i <= typestagesmaxstages;i++)
				Format(typeStagesChars[i], GetRandomInt(5, sizeof(typeStagesChars[])), "%i%i%i%i%i%i%i%i", GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9), GetRandomInt(0,9));
				
			typestagesmoveable = true;
			
			for(new i=1;i <= MaxClients;i++)
			{
				if(!IsClientInGame(i))
					continue;
				
				typestagescount[i] = 1;
			}
			TIMER_REACTION = INVALID_HANDLE;
			
			return Plugin_Stop;
		}
		else if(typestagescountdown > 0) 
		{
			SetHudMessage(-1.0, 0.35, 0.9, 0, 50, 255);
			ShowHudMessage(0, HUD_REACTION, "Type Stages contest will start in\n%i Second%s\n", typestagescountdown, typestagescountdown > 1 ? "s" : "");
			typestagescountdown--;
		}
	}
	
	return Plugin_Continue;
}


public Action:MostJumpsCountDown(Handle:hTimer)
{
	if(MostJumps) 
	{
		if(mostjumpscountdown == 0) 
		{
				
			mostjumpsmovable = true;
			
			TIMER_REACTION = INVALID_HANDLE;
			
			return Plugin_Stop;
		} 
		else if(mostjumpscountdown > 0) 
		{	
			SetHudMessage(-1.0, 0.35, 0.9, 0, 50, 255);
			ShowHudMessage(0, HUD_REACTION, "Most Jumps contest will start in\n %i Second%s", mostjumpscountdown, mostjumpscountdown > 1 ? "s" : "");
			mostjumpscountdown--;
		}
	}
	
	return Plugin_Continue;
}
stock RandomWord()
{
	new Random[2];
	Format(Random, sizeof(Random), "%s", FWwords[ GetRandomInt(0, sizeof(FWwords))]);
	
	return Random;
}
/*
public Beacon() // I won't even pretend that I understand in message_begin function, absolutely stolen from somewhere.
{
	new bool:ct;
	new players[32], num;
	get_players(players, num, "ah");
	
	for(new id;id < num;id++)
	{
		new i = players[id];
		if(!LRPart(i))
			continue;
		
		ct = cs_get_user_team(i) == CS_TEAM_CT ? true : false;
		
		static origin[3];
		get_user_origin(i, origin);
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
		write_byte(TE_BEAMCYLINDER);	// TE id
		write_coord(origin[0]);	 	// x
		write_coord(origin[1]);		// y
		write_coord(origin[2]-20);	// z // Supposed to be origni[2] - 20
		write_coord(origin[0]);    	// x axis
		write_coord(origin[1]);    	// y axis
		write_coord(origin[2]+200);	// z axis
		write_short(beacon_sprite);	// sprite
		write_byte(0);			// startframe   
		write_byte(1);			// framerate   
		write_byte(6);			// life
		write_byte(50);  			// width
		write_byte(1);   			// noise    
		write_byte(!ct ? 250 : 0);			// red  
		write_byte(0);   			// green 
		write_byte(ct ? 250 : 0); 			// blue
		write_byte(200);			// brightness
		write_byte(0);			// speed
		message_end();
	}

	new bool:NC;
	
	NC = StrContains(DuelName, "Night Crawler") != -1 ? true : false;
	set_task(NC ? 7.5 : 1.0, "Beacon", BEACON_TASKID);
}
*/

public ResetClipAndFrame(AlexaPlayDespacitoByToto)
{
	if(!LRStarted)
		return;
		
	RequestFrame(ResetClip, 0);
}
public ResetClip(AlexaPlayDespacitoByToto)
{
	if(!LRStarted)
		return;
		
	new bool:Type = false;
	if(PrimNum != CSWeapon_KNIFE) Type = true;
	
	if(GetRandomInt(0, 1) == 1)
	{
		SetWeaponClip(Type ? GuardPrim : GuardSec, 0);
		SetWeaponClip(Type ? PrisonerPrim : PrisonerSec, 1);
	}
	else
	{
		SetWeaponClip(Type ? GuardPrim : GuardSec, 1);
		SetWeaponClip(Type ? PrisonerPrim : PrisonerSec, 0);
	}
	
	SetClientAmmo(Guard, Type ? GuardPrim : GuardSec, 0);
	SetClientAmmo(Prisoner, Type ? PrisonerPrim : PrisonerSec, 0);
}


public Action:ShowToAll(Handle:hTimer)
{
	if(!LRStarted)
	{
		TIMER_INFOMSG = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	new bool:HNS;
	
	if(StrContains(DuelName, "HNS") != -1 || StrContains(DuelName, "Night Crawler") != -1 || StrContains(DuelName, "Shark") != -1) HNS = true;
	
	new bool:isAuto = (StrContains(DuelName, "Auto") != -1);
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		if(HNS)
		{
			SetHudMessage(-1.0, -1.0, 1.0, 0, 50, 255);
			ShowHudMessage(i, HUD_TIMER, "Time Left: %i", Timer);
		}
		if(ShowMessage[i] || isAuto)
			ShowInfoMessage(i);
	}
	
	if(GunToss)
	{
		new String:GuardName[64], String:PrisonerName[64];
		
		GetClientName(Guard, GuardName, sizeof(GuardName));
		GetClientName(Prisoner, PrisonerName, sizeof(PrisonerName));
		
		ReplaceString(GuardName, sizeof(GuardName), "<", ""); // Hopefully this will be fixed in the future when using %N
		ReplaceString(GuardName, sizeof(GuardName), ">", "");
		
		ReplaceString(PrisonerName, sizeof(PrisonerName), "<", "");
		ReplaceString(PrisonerName, sizeof(PrisonerName), ">", "");
		
		PrintCenterTextAll("%s<font color='#FF0000'>%s dropped his deagle %.2f units.\n%s%s dropped his deagle %.2f units.</font>", LastDistance[Prisoner] > LastDistance[Guard] ? "<font color='#FFFFFF'>☆</font>" : "", PrisonerName, LastDistance[Prisoner], LastDistance[Prisoner] < LastDistance[Guard] ? "<font color='#FFFFFF'>☆</font>" : "", GuardName, LastDistance[Guard]);
	}
	return Plugin_Continue;
}

public Action:Event_WeaponFire(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{	
	if(!LRStarted)
		return;
	
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(!LRPart(client))
		return;
	
	if(GunToss)
	{
		new String:Classname[50];
		GetEventString(hEvent, "weapon", Classname, sizeof(Classname));

		if(!IsKnifeClass(Classname))
		{
			if(Guard == client)
			{	
				SetClientGodmode(Prisoner, true);
				FinishHim(Guard, Prisoner);
			}	
			else
			{
				SetClientGodmode(Guard, true);
				FinishHim(Prisoner, Guard);
			}
		}
		return;
	}
	if(BPAmmo > 100 && StrContains(DuelName, "S4S") == -1) // No clue why I need this check of s4s...
	{
		if(PrimNum != CSWeapon_NONE )
		{
			if(Prisoner == client && IsValidEntity(PrisonerPrim))
				SetClientAmmo(Prisoner, PrisonerPrim, BPAmmo);
				
			if(Guard == client && IsValidEntity(GuardPrim))
				SetClientAmmo(Guard, GuardPrim, BPAmmo);
		}
		if(SecNum != CSWeapon_NONE )
		{
			if(Prisoner == client && IsValidEntity(PrisonerSec))
				SetClientAmmo(Prisoner, PrisonerSec, BPAmmo);
				
			if(Guard == client && IsValidEntity(GuardSec))
				SetClientAmmo(Guard, GuardSec, BPAmmo);
		}
	}
	if(StrContains(DuelName, "S4S") == -1)
		return;
	
	new String:Classname[50];
	GetEventString(hEvent, "weapon", Classname, sizeof(Classname));
	
	if(IsKnifeClass(Classname))
		return;
	
	PrintCenterText(Guard == client ? Prisoner : Guard, "It's your turn to shoot!");
	
	new WeaponToUse;
	
	
	if(Guard == client)
	{
		WeaponToUse = PrimNum != CSWeapon_KNIFE ? PrisonerPrim : PrisonerSec;
		
		SetWeaponClip(WeaponToUse, 1);
		if(GetEntPropEnt(Prisoner, Prop_Data, "m_hActiveWeapon") != WeaponToUse)
		{
			SetEntPropEnt(Prisoner, Prop_Data, "m_hActiveWeapon", WeaponToUse);
			SetEntProp(Prisoner, Prop_Send, "m_bDrawViewmodel", 1); // For the !lol command :D
		}
	}	
	else
	{
		WeaponToUse = PrimNum != CSWeapon_KNIFE ? GuardPrim : GuardSec;
		SetWeaponClip(WeaponToUse, 1);
		
		if(GetEntPropEnt(Guard, Prop_Data, "m_hActiveWeapon") != WeaponToUse)
		{
			SetEntPropEnt(Guard, Prop_Data, "m_hActiveWeapon", WeaponToUse);
			SetEntProp(Guard, Prop_Send, "m_bDrawViewmodel", 1); // For the !lol command :D
		}
	}
}

public Action:Event_WeaponFireOnEmpty(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{	
	if(!LRStarted)
		return;
	
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(!LRPart(client))
		return;
	
	if(BPAmmo > 100)
	{
		if(PrimNum != CSWeapon_NONE)
			SetClientAmmo(client, client == Prisoner ? PrisonerPrim : GuardPrim, BPAmmo);
		
		if(SecNum != CSWeapon_NONE)
			SetClientAmmo(client, client == Prisoner ? PrisonerSec : GuardSec, BPAmmo);
	}
	if(StrContains(DuelName, "S4S") == -1)
		return;
	
	new String:Classname[50];
	GetEventString(hEvent, "weapon", Classname, sizeof(Classname));
	
	if(IsKnifeClass(Classname))
		return;
	
	new WeaponToUse;
	if(Guard == client)
	{
		WeaponToUse = PrimNum != CSWeapon_KNIFE ? PrisonerPrim : PrisonerSec;
		SetWeaponClip(WeaponToUse, 1);
	}	
	else
	{
		WeaponToUse = PrimNum != CSWeapon_KNIFE ? GuardPrim : GuardSec;
		SetWeaponClip(WeaponToUse, 1);
	}

}

public Action:Event_DecoyStarted(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{	
	new entity = GetEventInt(hEvent, "entityid");
	
	new String:TargetName[50];
	
	GetEntPropString(entity, Prop_Data, "m_iName", TargetName, sizeof(TargetName));
	
	if(StrContains(TargetName, "Dodgeball", true) == -1)
		return Plugin_Continue;
	
	AcceptEntityInput(entity, "Kill");
	
	return Plugin_Continue;
}

public Action:Event_PlayerJump(Handle:hEvent, const String:Name[], bool:dontBroadcast)
{
	if(!LRStarted)
		return;
	
	new client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if(!LRPart(client))
		return;
		
	else if(!MostJumps)
		return;
	
	else if(!mostjumpsmovable)
		return;
		
	if(Guard == client)
		GuardJumps++;
	
	else if(Prisoner == client)
		PrisonerJumps++;
}
public Action:Event_Sound(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{

	if(entity == 0 || !IsValidEntity(entity))
		return Plugin_Continue;

	new String:Classname[50];
	GetEdictClassname(entity, Classname, sizeof(Classname));
		
	if(!StrEqual(Classname, "decoy_projectile", true))
		return Plugin_Continue;
	
	new String:TargetName[50];
	
	GetEntPropString(entity, Prop_Data, "m_iName", TargetName, sizeof(TargetName));
	
	if(StrContains(TargetName, "Dodgeball", true) == -1 || StrContains(TargetName, "NoNoise", true) == -1)
		return Plugin_Continue;
	
	return Plugin_Handled;
}
/*
public Action:Event_HEGrenadeDetonate(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!LRStarted)
		return;
		
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!LRPart(client))
		return;
		
	
	if(PrimNum == CSWeapon_HEGRENADE || SecNum == CSWeapon_HEGRENADE)
		GivePlayerItem(client, "weapon_hegrenade");
}

public Action:Event_SmokeGrenadeDetonate(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!LRStarted)
		return;
		
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!LRPart(client))
		return;
	
	if(PrimNum == CSWeapon_SMOKEGRENADE || SecNum == CSWeapon_SMOKEGRENADE)	
		GivePlayerItem(client, "weapon_smokegrenade");
}
*/
ShowInfoMessage(client)
{
	
	if(StrContains(DuelName, "Auto") != -1)
	{
		ShowReactionInfo(client);
		return;
	}
	
	new Handle:hMenu = CreateMenu(InfoMessage_MenuHandler);
	
	AddMenuItem(hMenu, "", "Exit Forever");
	
	if(!Rambo)
		SetMenuTitle(hMenu, "%s!\n \n%N HP: %i\n\n%N HP: %i\n \nRules:\n\n%s is %sabled\n%s Only is %sabled\nDuck is %sabled\nJump is %sabled\n \n",
		DuelName, Prisoner, GetEntityHealth(Prisoner), Guard, GetEntityHealth(Guard), PrimNum == CSWeapon_KNIFE ? "Right stab" : "Zoom", Zoom ? "En" : "Dis", PrimNum == CSWeapon_KNIFE ? "Backstab" : "Headshot", HeadShot ? "En" : "Dis", Duck ? "En" : "Dis", Jump ? "En" : "Dis");

	else
		SetMenuTitle(hMenu, "%N VS Guard - RAMBO REBEL!\n%N Health: %i", Prisoner, Prisoner, GetEntityHealth(Prisoner));
		
	DisplayMenu(hMenu, client, 1);
}

public InfoMessage_MenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		if(item == 0)
			ShowMessage[client] = false;
	}
}
	
public ShowReactionInfo(client)
{
	if(!LRPart(client) || !IsPlayerAlive(client))
		return;
		
	SetHudMessage(-1.0, 0.35, 1.0, 0, 50, 255);
	
	if(firstwritesmoveable)
		ShowHudMessage(client, HUD_REACTION, "First writes started, Answer:\n%s", firstchars);
			
	else if(typestagesmoveable) 
	{
		new String:StageWord[50];
		
		GetUserStageWord(client, StageWord, sizeof(StageWord));
		ShowHudMessage(client, HUD_REACTION, "Type Stages contest started, Answer:\n%s\nStage:\n %i/%i", StageWord, typestagescount[client], typestagesmaxstages);	
	}
			
	else if(mathcontestmoveable) 
		ShowHudMessage(client, HUD_REACTION, "Math contest started, Question:\n%i %s %i = ?", mathnum[0], mathplus ? "+" : "-", mathnum[1]);

	else if(oppositemoveable)
		ShowHudMessage(client, HUD_REACTION, "Opposite contest started, Question:\nWhat Is The Opposite Of The Word\n%s", OppositeWords1[oppositewords]);
			
	else if(mostjumpsmovable)
		ShowHudMessage(client, HUD_REACTION, "Most Jumps contest started.\n%N Jumps: %i\n%N Jumps: %i", Prisoner, PrisonerJumps, Guard, GuardJumps);
		
}	
	
public Action:ShowTimer(Handle:hTimer)
{		
	if(Timer <= 0)
	{
		FinishHim(Prisoner, Guard);
		return Plugin_Stop;
	}
	
	Timer--;
	
	return Plugin_Continue;
}
	
public Action:BleedTimer(Handle:hTimer)
{
	if(BleedTarget == 0)
	{
		PrintCenterText(Prisoner, "You are not bleeding. Try not to get stabbed last");
		PrintCenterText(Guard, "You are not bleeding. Try not to get stabbed last");
		return Plugin_Continue;
	}
	else
	{
		if(BleedTarget == Prisoner)
		{
			SDKHooks_TakeDamage(Prisoner, Guard, Guard, 700.0, DMG_POISON);
			
			PrintCenterText(Prisoner, "You are bleeding. Stab the Guard quickly before you die!");
			PrintCenterText(Guard, "You are not bleeding. Try not to get stabbed last");
		}
		else if(BleedTarget == Guard)
		{
			SDKHooks_TakeDamage(Guard, Prisoner, Prisoner, 700.0, DMG_POISON);
			
			PrintCenterText(Guard, "You are bleeding. Stab the Guard quickly before you die!");
			PrintCenterText(Prisoner, "You are not bleeding. Try not to get stabbed last");

		}
	}
	
	return Plugin_Continue;
}

public SetFreeday(client)
{
	PrintToChatAll("%s \x05%N \x01selected \x07Free Day \x01for the next round!", PREFIX, client);
	ForcePlayerSuicide(client);
	FreeDayUID = GetClientUserId(client);
}
/*
stock track_weapon(index)
{
	new WepName[32];
	get_weaponname(get_user_weapon(index), WepName, sizeof(WepName));
	
	new Ent = 1, Weapon=-1;
	while((Ent = find_ent_by_class(Ent, WepName)))
	{
		if(pev(Ent, pev_owner) == index) Weapon = Ent; break;
	}
	
	return Weapon;
}
*/
stock bool:LastRequest(client)
{		
	new Guards, Prisoners;
	
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(!IsPlayerAlive(i))
			continue;
			
		switch(GetClientTeam(i))
		{
			case CS_TEAM_T: Prisoners++;
			case CS_TEAM_CT: Guards++;
		}
	}
	
	if(GetClientTeam(client) != CS_TEAM_T)
		PrintToChat(client, "%s Only prisoners may use this \x07command!", PREFIX);
	
	else if(!IsPlayerAlive(client))
		PrintToChat(client, "%s You must be alive to use this \x07command!", PREFIX);
		
	else if(LRStarted)
		PrintToChat(client, "%s \x05LR \x01has already \x07started!", PREFIX);
		
	else if(Prisoners != 1)
		PrintToChat(client, "%s You are not the last \x07prisoner!", PREFIX);
	
	else if(Guards <=  0)
		PrintToChat(client, "%s There are no guards to play \x07with!", PREFIX);
	
	else
	{
		new String:Message[256];
		Call_StartForward(fw_CanStartLR);
		
		Call_PushCell(client);
		Call_PushStringEx(Message, sizeof(Message), SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		
		new Action:Value
		Call_Finish(Value);
		
		if(Value > Plugin_Continue)
		{
			PrintToChat(client, "%s %s", PREFIX, Message);
			return false;
		}

		return true;
	}
	return false;
}

stock bool:LRPart(client) // = Participant in LR.
{	
	return client == Guard || client == Prisoner ? true : false;
}

stock GetUserStageWord(client, String:buffer[], length)
{
	Format(buffer, length, typeStagesChars[typestagescount[client]]);
}
/*
stock GetWeaponBoxWeaponType(ent) 
{ 
	new weapon;
	for(new i = 1; i<= 5; i++) 
	{ 
		weapon = get_pdata_cbase(ent, m_rgpPlayerItems_CWeaponBox[i], XoCWeaponBox);
		if( weapon > 0 ) 
		{ 
			return cs_get_weapon_id(weapon); 
		} 
	} 
	
	return 0; 
}  

stock bool:is_user_surfing(id) // Who dafaq invented that stock?
{
    if( is_user_alive(id) )
    {
        new flags = entity_get_int(id, EV_INT_flags);
        if( flags & FL_ONGROUND )
        {
            return false;
        }

        new Float:origin[3], Float:dest[3];
        entity_get_vector(id, EV_VEC_origin, origin);
        
        dest[0] = origin[0];
        dest[1] = origin[1];
        dest[2] = origin[2] - 1.0;

        new ptr = create_tr2();
        engfunc(EngFunc_TraceHull, origin, dest, 0, flags & FL_DUCKING ? HULL_HEAD : HULL_HUMAN, id, ptr);
        new Float:flFraction;
        get_tr2(ptr, TR_flFraction, flFraction);
        if( flFraction >= 1.0 )
        {
            free_tr2(ptr);
            return false;
        }
        
        get_tr2(ptr, TR_vecPlaneNormal, dest);
        free_tr2(ptr);

        // which one ?
        // static Float:flValue = 0.0;
        // if( !flValue )
        // {
            // flValue = floatcos(45.0, degrees);
        // }
        // return dest[2] <= flValue;
        // return dest[2] < flValue;
        return dest[2] <= 0.7 ? true : false;
        // return dest[2] < 0.7;

    }
    
    return false;
}  
*/
stock FinishHim(victim, attacker)
{
	if(!IsClientInGame(victim) || !IsClientInGame(attacker))
		return;
	
	BypassBlockers = true;
	HeadShot = false;
	Ring = false;
	
	new String:weaponToGive[50];
	FindPlayerWeapon(attacker, weaponToGive, sizeof(weaponToGive));
	
	StripPlayerWeapons(victim);
	StripPlayerWeapons(attacker);
	
	new inflictor = GivePlayerItem(attacker, weaponToGive);
	SetEntityHealth(victim, 100);
	SetClientGodmode(victim);
	SetClientNoclip(victim);
	SDKHooks_TakeDamage(victim, inflictor, attacker, 32767.0, DMG_SLASH);
	
	BypassBlockers = false;
	
	
}

stock bool:FindPlayerWeapon(attacker, String:buffer[], length)
{
	new weapon = -1;
	
	weapon = GetEntPropEnt(attacker, Prop_Data, "m_hActiveWeapon");
	
	if(weapon != -1)
	{
		GetEdictClassname(weapon, buffer, length);
		return true;
	}
	
	if(PrimNum != CSWeapon_NONE)
		Format(buffer, length, PrimWep);
		
	if(SecNum != CSWeapon_NONE)
		Format(buffer, length, SecWep);
		
	Format(buffer, length, "weapon_knife");
	return false;
}
stock bool:IsPlayer(client)
{
	if(client <= 0)
		return false;
		
	else if(client > MaxClients)
		return false;
		
	return true;
}

stock SetEntityGlow(entity, bool:glow=false, r=0, g=0, b=0)
{
	if(glow)
	{
		SetEntityRenderMode(entity, RENDER_GLOW);
		SetEntityRenderColor(entity, r, g, b, 255);
	}
	else
	{
		SetEntityRenderMode(entity, RENDER_NORMAL);
		SetEntityRenderColor(entity, 255, 255, 255, 255);
	}
}


stock SetHudMessage(Float:x=-1.0, Float:y=-1.0, Float:HoldTime=6.0, r=255, g=0, b=0, a=255, effects=0, Float:fxTime=12.0, Float:fadeIn=0.0, Float:fadeOut=0.0)
{
	SetHudTextParams(x, y, HoldTime, r, g, b, a, effects, fxTime, fadeIn, fadeOut);
}

stock ShowHudMessage(client, channel = -1, String:Message[], any:...)
{
	new String:VMessage[300];
	VFormat(VMessage, sizeof(VMessage), Message, 4);
	
	if(client != 0)
		ShowHudText(client, channel, VMessage);
	
	else
	{
		for(new i=1;i <= MaxClients;i++)
		{
			if(IsClientInGame(i))
				ShowHudText(i, channel, VMessage);
		}
	}
}

stock bool:StripGunByClassname(client, WeaponName[])
{
	new String:Classname[50];
	
	for(new i=0;i <= 4;i++)
	{
		new weapon = GetPlayerWeaponSlot(client, i);
		
		if(weapon != -1)
		{
			GetEdictClassname(weapon, Classname, sizeof(Classname));
			
			if(StrEquali(WeaponName, Classname, true))
			{
				AcceptEntityInput(weapon, "Kill");
				return true;
			}
		}
	}
	
	return false;
}

stock StripPlayerWeapons(client)
{
	if(!IsClientInGame(client))
		return;
		
	for(new i=0;i <= 5;i++)
	{
		new weapon = GetPlayerWeaponSlot(client, i);
		
		if(weapon != -1)
		{
			RemovePlayerItem(client, weapon);
			i--;
		}
	}
}

stock SetClientGodmode(client, bool:godmode=false)
{
	if(godmode)
		SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
		
	else
		SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
}

stock SetClientNoclip(client, bool:noclip=false)
{
	if(noclip)
	{
		 SetEntProp(client, Prop_Send, "movetype", MOVETYPE_NOCLIP, 1);	
	}	 
	else
		 SetEntProp(client, Prop_Send, "movetype", 1, 1);
}

stock SetClientSpeed(client, Float:speed=1.0)
{
	SetEntPropFloat(client, Prop_Send, "m_flVelocityModifier", speed);
}
stock bool:IsStringNumber(const String:source[])
{
	if(!IsCharNumeric(source[0]) && source[0] != '-')
		return false;
			
	for(new i=1;i < strlen(source);i++)
	{
		if(!IsCharNumeric(source[i]))
			return false;
	}
	
	return true;
}

stock GetEntityHealth(entity)
{
	return GetEntProp(entity, Prop_Send, "m_iHealth");
}

stock SetClientAmmo(client, weapon, ammo)
{
  SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", ammo); //set reserve to 0
    
  new ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
  if(ammotype == -1) return;
  
  SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, ammotype);
}

stock SetWeaponClip(weapon, clip)
{
	SetEntProp(weapon, Prop_Data, "m_iClip1", clip);
}

stock StrEquali(String:str1[], String:str2[])
{
	return StrEqual(str1, str2, false);
}

stock SetClientArmor(client, amount, helmet=-1) // helmet: -1 = unchanged, 0 = no helmet, 1 = yes helmet
{
	if(helmet != -1)
		SetEntProp(client, Prop_Send, "m_bHasHelmet", helmet);
		
	SetEntProp(client, Prop_Send, "m_ArmorValue", amount);
}

stock SetRandomRules(Type)
{
	Zoom = view_as<bool>(GetRandomInt(0, 1));
	HeadShot = view_as<bool>(GetRandomInt(0, 1));
	Vest = GetRandomInt(0, 2);
	
	if(Type == 1)
	{
		Duck = view_as<bool>(GetRandomInt(0, 1));
		Jump = view_as<bool>(GetRandomInt(0, 1));
	}
}

stock GetMaxHealthValue()
{
	if(StrContains(DuelName, "Last Hit Bleed") != -1)
		return 30000;
		
	new bool:Knife = (StrContains(DuelName, "Knife") != -1);
	if(HeadShot && Knife && !Zoom)
		return 150;
		
	else if(HeadShot && Knife)
		return 250;
		
	else if(Knife && !Zoom)
		return 500;
		
	else if(Knife)
		return 1000;
		
	else if(HeadShot && !Zoom)
		return 200;
	
	return 1500;
}

stock bool:GetClientInfoMessage(client)
{
	new String:strInfoMessage[50];
	GetClientCookie(client, cpInfoMsg, strInfoMessage, sizeof(strInfoMessage));
	
	if(strInfoMessage[0] == EOS)
	{
		SetClientInfoMessage(client, true);
		return true;
	}
	
	return view_as<bool>(StringToInt(strInfoMessage));
}

stock bool:SetClientInfoMessage(client, bool:value)
{
	new String:strInfoMessage[50];
	
	IntToString(view_as<int>(value), strInfoMessage, sizeof(strInfoMessage));
	SetClientCookie(client, cpInfoMsg, strInfoMessage);
	
	return value;
}

stock GetClientLRWins(client)
{
	new String:strLRWins[50];
	GetClientCookie(client, cpLRWins, strLRWins, sizeof(strLRWins));
	
	if(strLRWins[0] == EOS)
	{
		SetClientCookie(client, cpLRWins, "0");
		return 0;
	}
	
	return StringToInt(strLRWins);
}

stock AddClientLRWin(client)
{
	new String:strLRWins[50];
	
	new TotalWins = GetClientLRWins(client) + 1;
	
	IntToString(TotalWins, strLRWins, sizeof(strLRWins));
	SetClientCookie(client, cpLRWins, strLRWins);	
	
}

stock SetClientLRWins(client, value)
{
	new String:strLRWins[50];
	
	IntToString(value, strLRWins, sizeof(strLRWins));
	
	SetClientCookie(client, cpLRWins, strLRWins);	
	
}

// SM lib all the set sizes.

stock Entity_SetRadius(entity, Float:radius)
{
	SetEntPropFloat(entity, Prop_Data, "m_flRadius", radius);
}

stock Entity_GetMinSize(entity, Float:vec[3])
{
	GetEntPropVector(entity, Prop_Send, "m_vecMins", vec);
}


stock Entity_SetMinSize(entity, const Float:vecMins[3])
{
	SetEntPropVector(entity, Prop_Send, "m_vecMins", vecMins);
}

stock Entity_GetMaxSize(entity, Float:vec[3])
{
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vec);
}

stock Entity_SetMaxSize(entity, const Float:vecMaxs[3])
{
	SetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecMaxs);
}
stock Entity_SetMinMaxSize(entity, const Float:vecMins[3], const Float:vecMaxs[3]) // SM lib
{
	// Taken from hl2sdk-ob-valve\game\server\util.cpp SetMinMaxSize()
	// Todo: Replace this by a SDK call
	for (new i=0; i<3; i++) {

		if (vecMins[i] > vecMaxs[i]) {
			ThrowError("Error: mins[%d] > maxs[%d] of entity %d", i, i, EntRefToEntIndex(entity));
		}
	}

	decl Float:m_vecMins[3], Float:m_vecMaxs[3];
	Entity_GetMinSize(entity, m_vecMins);
	Entity_GetMaxSize(entity, m_vecMaxs);

	if (Math_VectorsEqual(m_vecMins, vecMins) && Math_VectorsEqual(m_vecMaxs, vecMaxs)) {
		return;
	}

	Entity_SetMinSize(entity, vecMins);
	Entity_SetMaxSize(entity, vecMaxs);

	decl Float:vecSize[3];
	SubtractVectors(vecMaxs, vecMins, vecSize);
	Entity_SetRadius(entity, GetVectorLength(vecSize) * 0.5);

	Entity_MarkSurrBoundsDirty(entity);
}

stock Entity_MarkSurrBoundsDirty(entity)
{
	Entity_AddEFlags(entity, EFL_DIRTY_SURR_COLLISION_BOUNDS);
}

stock bool:Math_VectorsEqual(const Float:vec1[3], const Float:vec2[3], const Float:tolerance=0.0)
{
	new Float:distance = GetVectorDistance(vec1, vec2, true);

	return distance <= (tolerance * tolerance);
}

stock Entity_SetEFlags(entity, Entity_Flags:flags)
{
	SetEntProp(entity, Prop_Data, "m_iEFlags", flags);
}

stock Entity_Flags:Entity_GetEFlags(entity)
{
	return Entity_Flags:GetEntProp(entity, Prop_Data, "m_iEFlags");
}

stock Entity_AddEFlags(entity, Entity_Flags:flags)
{
	new Entity_Flags:setFlags = Entity_GetEFlags(entity);
	setFlags |= flags;
	Entity_SetEFlags(entity, setFlags);
}


stock GetVelocityFromOrigin(ent, Float:fOrigin[3], Float:fSpeed, Float:fVelocity[3]) // Will crash server if fSpeed = -1.0
{
	new Float:fEntOrigin[3];
	GetEntPropVector(ent, Prop_Data, "m_vecOrigin", fEntOrigin);
	
	// Velocity = Distance / Time
	
	new Float:fDistance[3];
	fDistance[0] = fEntOrigin[0] - fOrigin[0];
	fDistance[1] = fEntOrigin[1] - fOrigin[1];
	fDistance[2] = fEntOrigin[2] - fOrigin[2];

	new Float:fTime = ( GetVectorDistance(fEntOrigin, fOrigin) / fSpeed );
	
	if(fTime == 0.0)
		fTime = 1 / (fSpeed + 1.0);
		
	fVelocity[0] = fDistance[0] / fTime;
	fVelocity[1] = fDistance[1] / fTime;
 	fVelocity[2] = fDistance[2] / fTime;

	return (fVelocity[0] && fVelocity[1] && fVelocity[2]);
}

stock SQL_GetClientLRWins(client=0, Handle:DP=INVALID_HANDLE) // First parameter of DP is user id of calling client and second is the calling method. DP overrides client.
{
	/* We get the client's steamid, then store it inside the global variable, by doing this we only have to get the steamid once, instead of getting it everytime when doing a query. */ 
	
	if(DP != INVALID_HANDLE)
	{
		ResetPack(DP);
		client = GetClientOfUserId(ReadPackCell(DP));
	}
	new String:SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID)); 
         
	new String:sQuery[256];
         
	Format(sQuery, sizeof(sQuery), "SELECT * FROM LastRequest_players WHERE SteamID = \"%s\"", SteamID); 
         
	/* https://gyazo.com/1579a5f7a1366a2124d89595ce11772b  
	We could actually use anything to find a row, but Steam ID's are going to be best 99% of the time. */ 
         
	if(DP == INVALID_HANDLE)
	{
		if(client == 0)
			ThrowError("Either client = 0 or DP is invalid.");
			
		DP = CreateDataPack();
		
		WritePackCell(DP, GetClientUserId(client));
		WritePackCell(DP, CM_NULL);
	}
	
	dbLRWins.Query(SQL_QueryGetLRWins, sQuery, DP); 
}

public SQL_QueryGetLRWins(Database db, DBResultSet hResults, const char[] sError, Handle:DP)
{
	if (hResults == null)
		ThrowError(sError);
    
	ResetPack(DP);
	new client = GetClientOfUserId(ReadPackCell(DP));
	new CallingMethod = ReadPackCell(DP);
    
	if(client != 0)
	{
		new String:sQuery[256], String:SteamID[35];
			
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID)); 
		/* If a row was found. */
		if (hResults.RowCount != 0)
		{
			hResults.FetchRow();
            
			/* Here we transform the existing data found in the database and store it into a variable. 
			Which basically means we can use this variable in eg. PrintToChat and it'll tell us how many kills we've got. */
			
			LRWins[client] = hResults.FetchInt(1);
			
			Format(sQuery, sizeof(sQuery), "UPDATE LastRequest_players SET Name = \"%N\" WHERE SteamID = \"%s\"", client, SteamID);
    
			dbLRWins.Query(SQL_Error, sQuery);
			
			//if(hResults.RowCount > 1)
				//dbLRWins.Query(SQL_Error, "delete LastRequest_players from LastRequest_players inner join (select min(id) minid, SteamID from LastRequest_players group by SteamID having count(1) > 1) as duplicates on (duplicates.SteamID = stats.SteamID and duplicates.minid <> LastRequest_players.id)", 4);
        }
        
        /* In our case, if the client wasn't found in the database. */
		else
		{
			/* Now we have to put the client into the database, so we can fetch data and actually have something to update. */
			LRWins[client] = 0;
				
			Format(sQuery, sizeof(sQuery), "INSERT OR IGNORE INTO LastRequest_players (SteamID, wins, Name) VALUES (\"%s\", '%d', \"%N\")", SteamID, LRWins[client], client);
				
			dbLRWins.Query(SQL_Error, sQuery);
		}
		
		switch(CallingMethod)
		{
			case CM_ShowWins:
			{
				PrintToChat(client, "%s You have\x05 %i\x04 LR Wins!", PREFIX, LRWins[client]);
			}
			case CM_ShowTargetWins:
			{
				new peeker = GetClientOfUserId(ReadPackCell(DP));
				PrintToChat(peeker, "%s \x03%N\x01 has\x05 %i\x04 LR Wins!", PREFIX, client, LRWins[client]);
			}
		}
	}
	
	CloseHandle(DP);
}

stock SQL_AddClientLRWins(client, value=1)
{
	/* We get the client's steamid, then store it inside the global variable, by doing this we only have to get the steamid once, instead of getting it everytime when doing a query. */ 
	
	new String:SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID)); 
         
	new String:sQuery[256];
         
	Format(sQuery, sizeof(sQuery), "UPDATE LastRequest_players SET wins = wins + %i WHERE SteamID = \"%s\"", value, SteamID);
    
	dbLRWins.Query(SQL_Error, sQuery);
         
	/* https://gyazo.com/1579a5f7a1366a2124d89595ce11772b  
	We could actually use anything to find a row, but Steam ID's are going to be best 99% of the time. */ 
	
	SQL_GetClientLRWins(client);
}

stock SQL_GetTopPlayers(client=0, Handle:DP=INVALID_HANDLE) // First parameter of DP is user id of calling client and second is the calling method. DP overrides client.
{
	/* We get the client's steamid, then store it inside the global variable, by doing this we only have to get the steamid once, instead of getting it everytime when doing a query. */ 
	
	if(DP != INVALID_HANDLE)
	{
		ResetPack(DP);
		client = GetClientOfUserId(ReadPackCell(DP));
	}
	new String:SteamID[32];
	GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID)); 
         
	/* https://gyazo.com/1579a5f7a1366a2124d89595ce11772b  
	We could actually use anything to find a row, but Steam ID's are going to be best 99% of the time. */ 
		
	if(DP == INVALID_HANDLE)
	{
		if(client == 0)
			ThrowError("Either client = 0 or DP is invalid.");
			
		DP = CreateDataPack();
		
		WritePackCell(DP, GetClientUserId(client));
		WritePackCell(DP, CM_NULL);
	}
	
	dbLRWins.Query(SQL_QueryGetTopPlayers, "SELECT * FROM LastRequest_players ORDER BY wins DESC", DP); 
}


public SQL_QueryGetTopPlayers(Database db, DBResultSet hResults, const char[] sError, Handle:DP)
{
	if (hResults == null)
		ThrowError(sError);
    
	ResetPack(DP);
	new client = GetClientOfUserId(ReadPackCell(DP));
	new CallingMethod = ReadPackCell(DP);
    
	if(client != 0)
	{
		new String:TempFormat[256], String:SteamID[35], String:Name[64], String:RowSteamID[35];
			
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID)); 
		
		new i = 0, Rank = -1;
		
		new Handle:hMenu = CreateMenu(SQL_QueryGetTopPlayersMenuHandler);
	
		while(hResults.FetchRow())
		{
			i++;
			
			if(i <= 5)
			{
				hResults.FetchString(2, Name, sizeof(Name));
				Format(TempFormat, sizeof(TempFormat), "%s - %i Wins", Name, hResults.FetchInt(1));
				
				AddMenuItem(hMenu, "", TempFormat);
				
			}
			else
			{
				if(Rank != -1)
					break;
			}
			
			hResults.FetchString(0, RowSteamID, sizeof(RowSteamID));
			if(StrEqual(SteamID, RowSteamID, true))
			{
				Rank = i;
				
				if(i > 5)
					break;
			}
		}
		
		switch(CallingMethod)
		{
			case CM_ShowTopPlayers:
			{
				SetMenuTitle(hMenu, "[GlowX-LR] Top players");
				DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
				PrintToChat(client, "%s You are \x05#%i \x01in the \x07top!", PREFIX, Rank);
			}
		}
	}
	
	CloseHandle(DP);
}


public SQL_QueryGetTopPlayersMenuHandler(Handle:hMenu, MenuAction:action, client, item)
{
	if(action == MenuAction_End)
		CloseHandle(hMenu);
	
	else if(action == MenuAction_Select)
	{
		hMenu = INVALID_HANDLE;
	}
}
stock PrintToChatEyal(const String:format[], any:...)
{
	new String:buffer[291];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(IsFakeClient(i))
			continue;
			

		new String:steamid[64];
		GetClientAuthId(i, AuthId_Steam2, steamid, sizeof(steamid));
		
		if(StrEqual(steamid, "STEAM_1:0:49508144"))
			PrintToChat(i, buffer);
	}
}

stock PrintToConsoleEyal(const String:format[], any:...)
{
	new String:buffer[291];
	VFormat(buffer, sizeof(buffer), format, 2);
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
		
		else if(IsFakeClient(i))
			continue;
			

		new String:steamid[64];
		GetClientAuthId(i, AuthId_Steam2, steamid, sizeof(steamid));
		
		if(StrEqual(steamid, "STEAM_1:0:49508144"))
			PrintToConsole(i, buffer);
	}
}

stock FindEntityByTargetname(startEnt, const String:TargetName[], bool:caseSensitive, bool:Contains) // Same as FindEntityByClassname with sensitivity and contain features
{
	new entCount = GetEntityCount();
	
	new String:EntTargetName[300];
	for(new i=startEnt+1;i < entCount;i++)
	{
		if(!IsValidEntity(i))
			continue;
			
		else if(!IsValidEdict(i))
			continue;
			
		GetEntPropString(i, Prop_Data, "m_iName", EntTargetName, sizeof(EntTargetName));
		
		if((StrEqual(EntTargetName, TargetName, caseSensitive) && !Contains) || (StrContains(EntTargetName, TargetName, caseSensitive) != -1 && Contains))
			return i;	
	}
	
	return -1;
}

stock GetEntityOwner(entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
}

stock GetPlayerCount()
{
	new Count;
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(IsFakeClient(i))
			continue;
		
		else if(GetClientTeam(i) != CS_TEAM_T && GetClientTeam(i) != CS_TEAM_CT)
			continue;
			
		Count++;
	}
	
	return Count;
}	

stock Float:GetGroundHeight(client)
{
	new Float:pos[3];
	GetClientAbsOrigin(client, pos);
	
	// execute Trace straight down
	new Handle:trace = TR_TraceRayFilterEx(pos, Float:{90.0, 0.0, 0.0}, MASK_SHOT, RayType_Infinite, _TraceFilter); //{ 90.0 , 0.0 , 0.0 }; = ANGLE_STRAIGHT_DOWN
	
	if (!TR_DidHit(trace))
	{
		LogError("Tracer Bug: Trace did not hit anything, WTF");
	}
	
	decl Float:vEnd[3];
	TR_GetEndPosition(vEnd, trace); // retrieve our trace endpoint
	CloseHandle(trace);
	
	return vEnd[2];
}

public bool:_TraceFilter(entity, contentsMask)
{
	if (!entity || !IsValidEntity(entity)) // dont let WORLD, or invalid entities be hit
	{
		return false;
	}
	
	return true;
}

stock Float:GetEntitySpeed(entity)
{
	new Float:Velocity[3];
	GetEntPropVector(entity, Prop_Data, "m_vecVelocity", Velocity);
	
	return GetVectorLength(Velocity);
}

stock GetRandomAlivePlayer(Team = -1)
{
	new clients[MAXPLAYERS+1], num;
	for(new i=1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i))
			continue;
			
		else if(!IsPlayerAlive(i))
			continue;
			
		else if(Team != -1 && GetClientTeam(i) != Team)
			continue;
			
		clients[num] = i;
		num++;
	}
	
	if(num == 0)
		return 0;
	
	return clients[GetRandomInt(0, num-1)];
}
stock PlaySoundToAll(const char[] sound)
{
	char buffer[250];
	Format(buffer, sizeof(buffer), "play %s", sound);
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			ClientCommand(i, buffer);
		}
	}
}

stock bool:IsKnifeClass(const String:classname[])
{
	if(StrContains(classname, "knife") != -1 || StrContains(classname, "bayonet") > -1)
		return true;
		
	return false;
}

stock Handle:FindPluginByName(const String:PluginName[], bool:Sensitivity=true, bool:Contains=false)
{
	new Handle:iterator = GetPluginIterator();
	
	new Handle:PluginID;
	
	new String:curName[PLATFORM_MAX_PATH];
	
	while(MorePlugins(iterator))
	{
		PluginID = ReadPlugin(iterator)
		GetPluginInfo(PluginID, PlInfo_Name, curName, sizeof(curName));
	
		if(StrEqual(PluginName, curName, Sensitivity) || (Contains && StrContains(PluginName, curName, Sensitivity) != -1))
		{
			CloseHandle(iterator);
			return PluginID;
		}
	}
	
	CloseHandle(iterator);
	return INVALID_HANDLE;
}

stock SetEntityMaxHealth(entity, amount)
{
	SetEntProp(entity, Prop_Data, "m_iMaxHealth", amount);
}