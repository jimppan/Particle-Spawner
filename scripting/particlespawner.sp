#pragma semicolon 1

#define PLUGIN_AUTHOR "Rachnus"
#define PLUGIN_VERSION "1.0"

//#define DEBUG

#include <sourcemod>
#include <sdktools>
#include <cstrike>
//#include <sdkhooks>

#pragma newdecls required

#define PS_PREFIX " \x09[\x04Particle Spawner\x09]"

EngineVersion g_Game;
KeyValues g_Particles;

float g_fUnitsToMove[MAXPLAYERS + 1];
bool g_bMoveDirection[MAXPLAYERS + 1];
bool g_bConfigChanged;

public Plugin myinfo = 
{
	name = "Particle Spawner v1.0",
	author = PLUGIN_AUTHOR,
	description = "Spawns particles around the map that are defined in the config",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rachnus"
};

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	if(g_Game != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");	
	}
	
	HookEvent("round_start", Event_RoundStart);
	RegAdminCmd("sm_getposition", Command_GetPosition, ADMFLAG_BAN);
	RegAdminCmd("sm_getaimposition", Command_GetAimPosition, ADMFLAG_BAN);
	RegAdminCmd("sm_getpos", Command_GetPosition, ADMFLAG_BAN);
	RegAdminCmd("sm_getaimpos", Command_GetAimPosition, ADMFLAG_BAN);
	RegAdminCmd("sm_getaimentity", Command_GetAimEntity, ADMFLAG_BAN);
	RegAdminCmd("sm_editparticles", Command_EditParticles, ADMFLAG_ROOT);
	RegAdminCmd("sm_particleeditor", Command_EditParticles, ADMFLAG_ROOT);
	RegAdminCmd("sm_saveparticles", Command_SaveParticles, ADMFLAG_ROOT);
	RegAdminCmd("sm_revertparticles", Command_RevertParticles, ADMFLAG_ROOT);
	RegAdminCmd("sm_revertchanges", Command_RevertParticles, ADMFLAG_ROOT);
	RegAdminCmd("sm_changename", Command_ChangeName, ADMFLAG_ROOT);
	RegAdminCmd("sm_changeeffect", Command_ChangeEffect, ADMFLAG_ROOT);
	RegAdminCmd("sm_changeffect", Command_ChangeEffect, ADMFLAG_ROOT);
	ReadParticleConfig();
}

//////////////////
//	CALLBACKS	//
//////////////////
public Action Command_GetPosition(int client, int args)
{
	float pos[3];
	GetClientAbsOrigin(client, pos);
	PrintToChat(client, "%s \x0C%f %f %f", PS_PREFIX, pos[0], pos[1], pos[2]);
	
	return Plugin_Handled;
}

public Action Command_GetAimPosition(int client, int args)
{
	float eyeAngles[3], eyePos[3];
	GetClientEyeAngles(client, eyeAngles);
	GetClientEyePosition(client, eyePos);
	float end[3];
	Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_ALL, RayType_Infinite, TraceFilterNotSelf, client);
	if(TR_DidHit(trace))
		TR_GetEndPosition(end, trace);
	CloseHandle(trace);
		
	PrintToChat(client, "%s \x0C%f %f %f", PS_PREFIX, end[0], end[1], end[2]);
	
	return Plugin_Handled;
}

public Action Command_GetAimEntity(int client, int args)
{
	float eyeAngles[3], eyePos[3];
	GetClientEyeAngles(client, eyeAngles);
	GetClientEyePosition(client, eyePos);

	Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_ALL, RayType_Infinite, TraceFilterNotSelf, client);
	if(TR_DidHit(trace))
	{
		int ent = TR_GetEntityIndex(trace);
		if(ent > 0)
		{
			char szName[128];
			float pos[3];
			GetEntPropString(ent, Prop_Data, "m_iName", szName, sizeof(szName));
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
			PrintToChat(client, "%s Entity Name: \x0C%s", PS_PREFIX, szName);
			PrintToChat(client, "%s Entity Index: \x0C%d", PS_PREFIX, ent);
			PrintToChat(client, "%s Entity Position: \x0C%f %f %f", PS_PREFIX, pos[0], pos[1], pos[2]);
		}
		else
			PrintToChat(client, "%s Could not find an entity", PS_PREFIX);
	}
	else
		PrintToChat(client, "%s Could not find an entity", PS_PREFIX);
	CloseHandle(trace);
	
	return Plugin_Handled;
}

public Action Command_EditParticles(int client, int args)
{
	MainEditor(client);
	return Plugin_Handled;
}

public Action Command_SaveParticles(int client, int args)
{
	SaveParticles(client);
	return Plugin_Handled;
}

public Action Command_RevertParticles(int client, int args)
{
	RevertParticles(client);
	return Plugin_Handled;
}

public Action Command_ChangeName(int client, int args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "%s \x09Usage: \x04sm_changename <particlename> <newname>", PS_PREFIX);
		return Plugin_Handled;
	}
	char arg[65], arg2[65], targetName[32], map[PLATFORM_MAX_PATH];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	g_Particles.Rewind();
	GetCurrentMap(map, sizeof(map));
	if(!g_Particles.JumpToKey(map, false))
	{
		ReplyToCommand(client, "%s \x09There are no particles for this map!", PS_PREFIX);
		return Plugin_Handled;
	}
	int iEnt = MAXPLAYERS + 1;
	bool found = false;
	while((iEnt = FindEntityByClassname(iEnt, "info_particle_system")) != -1)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if(StrEqual(targetName, arg) && g_Particles.JumpToKey(targetName, false))
		{
			SetEntPropString(iEnt, Prop_Data, "m_iName", arg2);
			g_Particles.SetSectionName(arg2);
			ReplyToCommand(client, "%s \x09Changed the name of particle \x0C%s \x09to \x0C%s\x09!", PS_PREFIX, targetName, arg2);
			found = true;
			g_bConfigChanged = true;
			g_Particles.GoBack();
		}
	}
	
	if(!found)
		ReplyToCommand(client, "%s \x09Could not find any particles with the name \x0C%s", PS_PREFIX, arg);
	
	return Plugin_Handled;
}

public Action Command_ChangeEffect(int client, int args)
{
	if(args != 2)
	{
		ReplyToCommand(client, "%s \x09Usage: \x04sm_changeeffect <particlename> <effect>", PS_PREFIX);
		return Plugin_Handled;
	}
	char arg[65], arg2[65], targetName[32], map[PLATFORM_MAX_PATH], szEffect[PLATFORM_MAX_PATH];
	GetCmdArg(1, arg, sizeof(arg));
	GetCmdArg(2, arg2, sizeof(arg2));
	float vecPos[3];
	g_Particles.Rewind();
	GetCurrentMap(map, sizeof(map));
	if(!g_Particles.JumpToKey(map, false))
	{
		ReplyToCommand(client, "%s \x09There are no particles for this map!", PS_PREFIX);
		return Plugin_Handled;
	}
	int iEnt = MAXPLAYERS + 1;
	int newParticle = INVALID_ENT_REFERENCE;
	bool found = false;
	while((iEnt = FindEntityByClassname(iEnt, "info_particle_system")) != -1)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if(StrEqual(targetName, arg) && g_Particles.JumpToKey(targetName, false) && iEnt != newParticle)
		{
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecPos);
			GetEntPropString(iEnt, Prop_Data, "m_iszEffectName", szEffect, sizeof(szEffect));
			SetEntPropString(iEnt, Prop_Data, "m_iszEffectName", arg2);
			g_Particles.SetString("effect", arg2);
			ReplyToCommand(client, "%s \x09Changed the effect of particle \x0C%s \x09from \x0C%s \x09to \x0C%s\x09!", PS_PREFIX, arg, szEffect, arg2);
			found = true;
			g_bConfigChanged = true;
			AcceptEntityInput(iEnt, "Kill");
			newParticle = SpawnParticle(arg2, arg, vecPos);
			g_Particles.GoBack();
		}
	}
	
	if(!found)
		ReplyToCommand(client, "%s \x09Could not find any particles with the name \x0C%s", PS_PREFIX, arg);
	
	return Plugin_Handled;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	SpawnParticles();
}

//////////////////
//   FORWARDS   //
//////////////////

public void OnClientPutInServer(int client)
{
	g_fUnitsToMove[client] = 0.0;
	g_bMoveDirection[client] = false;
}

public void OnMapStart()
{
	PrecacheAndDownloadParticles();
}

////////////////
//   STOCKS   //
////////////////
stock void PrecacheAndDownloadParticles()
{
	char szParticlesPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, szParticlesPath, sizeof(szParticlesPath), "configs/particlespawner/particles.ini");

	if(!FileExists(szParticlesPath))
		SetFailState("[particlespawner.smx] Could not load %s", szParticlesPath);

	File particleFile = OpenFile(szParticlesPath, "rt");

	if(!particleFile)
		SetFailState("[particlespawner.smx] Could not load %s", szParticlesPath);

	// Only called once no need for static
	char data[PLATFORM_MAX_PATH];
	
	while (!IsEndOfFile(particleFile)) 
	{
		ReadFileLine(particleFile, data, sizeof(data));
		TrimString(data);
		
		if( data[0] == '\0' || strncmp(data, "##", 2, false) == 0) 
			continue;
		
		AddFileToDownloadsTable(data);
		PrecacheGeneric(data, true);
		ReplaceString(data, sizeof(data), ".pcf", "", false);
		//Remove the paths and only keep the file name
		for (int i = strlen(data); i > 0; i--)
		{
			if(data[i] == '/' || data[i] == '\\')
			{
				strcopy(data, sizeof(data), data[i + 1]);
				break;
			}				
		}
#if defined DEBUG
		PrintToServer("PRECACHED: %s", data);
#endif
		PrecacheParticleSystem(data);
	}
	delete particleFile;
}

stock void ReadParticleConfig()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/particlespawner/particle_spawns.cfg");
	g_Particles = new KeyValues("Particles");
	
	if(!g_Particles.ImportFromFile(path))
		SetFailState("Could not open %s", path);
}

stock void SpawnParticles()
{
	g_Particles.Rewind();
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	if(!g_Particles.JumpToKey(map))
		return;
	
	if(g_Particles.GotoFirstSubKey())
	{
		char targetname[PLATFORM_MAX_PATH];
		char particle[PLATFORM_MAX_PATH];
		float pos[3];
		
		do 
		{
			g_Particles.GetSectionName(targetname, sizeof(targetname));
			g_Particles.GetString("effect", particle, sizeof(particle));
			g_Particles.GetVector("pos", pos);
			SpawnParticle(particle, targetname, pos);
		} while (g_Particles.GotoNextKey());
	}
}

stock int SpawnParticle(const char[] effect, const char[] targetname, float pos[3])
{
	int particle = CreateEntityByName("info_particle_system");
	
	DispatchKeyValue(particle , "start_active", "0");
	DispatchKeyValue(particle, "effect_name", effect);
	DispatchKeyValue(particle, "targetname", targetname); 
	DispatchSpawn(particle);
	
	TeleportEntity(particle, pos, NULL_VECTOR,NULL_VECTOR);
	
	ActivateEntity(particle);
	AcceptEntityInput(particle, "Start");
	return particle;
}

stock void SaveParticles(int client)
{
	if(!g_bConfigChanged)
	{
		PrintToChat(client, "%s No changes have been made!", PS_PREFIX);
		return;
	}
	
	g_Particles.Rewind();
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/particlespawner/particle_spawns.cfg");
	
	if(!g_Particles.ExportToFile(path))
		SetFailState("Could not export to %s", path);
	g_bConfigChanged = false;
	PrintToChat(client, "%s Particles saved!", PS_PREFIX);
}

stock void SaveParticle(int particle, const char[] oldname, const char[] effect)
{
	if(particle == INVALID_ENT_REFERENCE)
		return;
	char szName[PLATFORM_MAX_PATH];
	char szEffect[PLATFORM_MAX_PATH];
	float pos[3];
	GetEntPropString(particle, Prop_Data, "m_iName", szName, sizeof(szName));
	GetEntPropString(particle, Prop_Data, "m_iszEffectName", szEffect, sizeof(szEffect));
	GetEntPropVector(particle, Prop_Data, "m_vecOrigin", pos);
#if defined DEBUG
	PrintToServer("PARTICLE %s SAVED!", szName);
#endif
	g_bConfigChanged = true;
	g_Particles.Rewind();
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	g_Particles.JumpToKey(map, true);
	g_Particles.JumpToKey(oldname, true);
	
	g_Particles.SetSectionName(szName);
	g_Particles.SetString("effect", szEffect);
	g_Particles.SetVector("pos", pos);
}

stock void DeleteParticle(int particle)
{
	if(particle == INVALID_ENT_REFERENCE)
		return;
		
	g_bConfigChanged = true;
	char szName[PLATFORM_MAX_PATH];
	GetEntPropString(particle, Prop_Data, "m_iName", szName, sizeof(szName));
#if defined DEBUG
	PrintToServer("PARTICLE %s DELETED!", szName);
#endif
	
	g_Particles.Rewind();
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	g_Particles.JumpToKey(map, true);
	g_Particles.DeleteKey(szName);
	AcceptEntityInput(particle, "Kill");
}

stock void RevertParticles(int client)
{
	if(!g_bConfigChanged)
	{
		PrintToChat(client, "%s No changes have been made!", PS_PREFIX);
		return;
	}
	
	g_Particles.Rewind();
	char targetName[32], map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	if(!g_Particles.JumpToKey(map, false))
		return;
	int iEnt = MAXPLAYERS + 1;
	while((iEnt = FindEntityByClassname(iEnt, "info_particle_system")) != -1)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if(!g_Particles.JumpToKey(targetName, false))
		{
			g_Particles.GoBack();
			continue;
		}
		g_Particles.GoBack();
		AcceptEntityInput(iEnt, "Kill");
#if defined DEBUG
	PrintToServer("KILLED PARTICLE INDEX :%d", iEnt);
#endif
	}

	ReadParticleConfig();
	SpawnParticles();
	g_bConfigChanged = false;
	PrintToChat(client, "%s Particle changes reverted!", PS_PREFIX);
}

stock void TeleportEntityToAim(int client, int entity)
{
	float eyeAngles[3], eyePos[3];
	GetClientEyeAngles(client, eyeAngles);
	GetClientEyePosition(client, eyePos);
	float end[3];
	Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_ALL, RayType_Infinite, TraceFilterNotSelf, client);
	if(TR_DidHit(trace))
	{
		TR_GetEndPosition(end, trace);
		g_bConfigChanged = true;
		TeleportEntity(entity, end, NULL_VECTOR, NULL_VECTOR);
	}
	CloseHandle(trace);
}

stock int PrecacheParticleSystem(const char[] particleSystem)
{
    static int particleEffectNames = INVALID_STRING_TABLE;

    if (particleEffectNames == INVALID_STRING_TABLE) {
        if ((particleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) {
            return INVALID_STRING_INDEX;
        }
    }

    int index = FindStringIndex2(particleEffectNames, particleSystem);
    if (index == INVALID_STRING_INDEX) {
        int numStrings = GetStringTableNumStrings(particleEffectNames);
        if (numStrings >= GetStringTableMaxStrings(particleEffectNames)) {
            return INVALID_STRING_INDEX;
        }
        
        AddToStringTable(particleEffectNames, particleSystem);
        index = numStrings;
    }
    
    return index;
}

stock int FindStringIndex2(int tableidx, const char[] str)
{
    char buf[1024];
    
    int numStrings = GetStringTableNumStrings(tableidx);
    for (int i=0; i < numStrings; i++) {
        ReadStringTable(tableidx, i, buf, sizeof(buf));
        
        if (StrEqual(buf, str)) {
            return i;
        }
    }
    
    return INVALID_STRING_INDEX;
}

public bool TraceFilterNotSelf(int entityhit, int mask, any entity)
{
	if(entity >= 0 && entityhit != entity)
		return true;
	
	return false;
}

///////////
// MENUS //
///////////
public void MainEditor(int client)
{
	Menu menu = new Menu(MainEditorMenuHandler);
	menu.SetTitle("Particle Editor");
	menu.AddItem("", "Particles");
	menu.AddItem("", "Save Particles");
	menu.AddItem("", "Revert All Changes");
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public void ParticleEditor(int client)
{
	g_Particles.Rewind();
	int iEnt = MAXPLAYERS + 1;
	char targetName[32], szEntityRef[32], map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	if(!g_Particles.JumpToKey(map, false))
		return;
	Menu menu = new Menu(ParticleMenuHandler);
	menu.SetTitle("Particles");
	while((iEnt = FindEntityByClassname(iEnt, "info_particle_system")) != -1)
	{
		GetEntPropString(iEnt, Prop_Data, "m_iName", targetName, sizeof(targetName));
		if(!g_Particles.JumpToKey(targetName, false))
		{
			g_Particles.GoBack();
			continue;
		}
			
		g_Particles.GoBack();
		Format(szEntityRef, sizeof(szEntityRef), "%d", EntIndexToEntRef(iEnt));
		menu.AddItem(szEntityRef, targetName);
	}
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public void EditParticle(int client, int particleEntity)
{
	char szMenuTitle[128], szUnits[32], szEntityRef[32], szMoveDirection[32];
	GetEntPropString(particleEntity, Prop_Data, "m_iName", szMenuTitle, sizeof(szMenuTitle));
	Format(szMenuTitle, sizeof(szMenuTitle), "Particle: %s", szMenuTitle);
	Format(szUnits, sizeof(szUnits), "Units To Move: %f", g_fUnitsToMove[client]);
	Format(szEntityRef, sizeof(szEntityRef), "%d", EntIndexToEntRef(particleEntity));
	Format(szMoveDirection, sizeof(szMoveDirection), "Move Direction: %s", (g_bMoveDirection[client] ? "Positive":"Negative"));
	Menu menu = new Menu(EditorMenuHandler);
	menu.SetTitle(szMenuTitle);
	menu.AddItem(szEntityRef, "Move Up/Down");
	menu.AddItem(szEntityRef, "Move Left/Right");
	menu.AddItem(szEntityRef, "Move Forward/Back");
	menu.AddItem(szEntityRef, szUnits);
	menu.AddItem(szEntityRef, szMoveDirection);
	menu.AddItem(szEntityRef, "Bring Particle To Aim");
	menu.AddItem(szEntityRef, "Delete Particle");
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MainEditorMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch(param2)
			{
				case 0:
				{
					g_Particles.Rewind();
					char map[PLATFORM_MAX_PATH];
					GetCurrentMap(map, sizeof(map));
					if(!g_Particles.JumpToKey(map, false) || !g_Particles.GotoFirstSubKey())
					{
						PrintToChat(param1, "%s There are no particles setup for this map!", PS_PREFIX);
						MainEditor(param1);
						return 0;
					}
					ParticleEditor(param1);
				}
				case 1:
				{
					SaveParticles(param1);
					MainEditor(param1);
				}
				case 2:
				{
					RevertParticles(param1);
					MainEditor(param1);
				}
			}	
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public int EditorMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char szInfo[128];
			GetMenuItem(menu, param2, szInfo, sizeof(szInfo));
			
			int entity = EntRefToEntIndex(StringToInt(szInfo));
			if(entity == INVALID_ENT_REFERENCE)
				return 0;
			
			char szName[PLATFORM_MAX_PATH];
			char szEffect[PLATFORM_MAX_PATH];
			float pos[3];
			GetEntPropString(entity, Prop_Data, "m_iName", szName, sizeof(szName));
			GetEntPropString(entity, Prop_Data, "m_iszEffectName", szEffect, sizeof(szEffect));
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
			
			switch(param2)
			{
				case 0:
				{
					pos[2] = (g_bMoveDirection[param1] ? (pos[2] + g_fUnitsToMove[param1]) : (pos[2] - g_fUnitsToMove[param1]));
					TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
					SaveParticle(entity, szName, szEffect);
					EditParticle(param1, entity);
				}
				case 1:
				{
					pos[1] = (g_bMoveDirection[param1] ? (pos[1] + g_fUnitsToMove[param1]) : (pos[1] - g_fUnitsToMove[param1]));
					TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
					SaveParticle(entity, szName, szEffect);
					EditParticle(param1, entity);
				}
				case 2:
				{
					pos[0] = (g_bMoveDirection[param1] ? (pos[0] + g_fUnitsToMove[param1]) : (pos[0] - g_fUnitsToMove[param1]));
					TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
					SaveParticle(entity, szName, szEffect);
					EditParticle(param1, entity);
				}
				case 3:
				{
					if(g_fUnitsToMove[param1] == 0.0)
						g_fUnitsToMove[param1] = 0.1;
					else if(g_fUnitsToMove[param1] == 0.1)
						g_fUnitsToMove[param1] = 0.5;
					else if(g_fUnitsToMove[param1] == 0.5)
						g_fUnitsToMove[param1] = 1.0;
					else if(g_fUnitsToMove[param1] == 1.0)
						g_fUnitsToMove[param1] = 5.0;
					else if(g_fUnitsToMove[param1] == 5.0)
						g_fUnitsToMove[param1] = 10.0;
					else if(g_fUnitsToMove[param1] == 10.0)
						g_fUnitsToMove[param1] = 50.0;
					else if(g_fUnitsToMove[param1] == 50.0)
						g_fUnitsToMove[param1] = 0.0;	
					EditParticle(param1, entity);
				}
				case 4:
				{
					g_bMoveDirection[param1] = !g_bMoveDirection[param1];
					EditParticle(param1, entity);
				}
				case 5:
				{
					TeleportEntityToAim(param1, entity);
					MainEditor(param1);
				}
				case 6:
				{
					DeleteParticle(entity);
					PrintToChat(param1, "%s Particle \x0C%s \x09deleted!", PS_PREFIX, szName);
					MainEditor(param1);
				}
			}	
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	switch(param2)
	{
		case MenuCancel_ExitBack:
		{
			ParticleEditor(param1);
		}
	}
	return 0;
}

public int ParticleMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{	
			char szInfo[128];
			GetMenuItem(menu, param2, szInfo, sizeof(szInfo));
			
			int entity = EntRefToEntIndex(StringToInt(szInfo));
			if(entity == INVALID_ENT_REFERENCE)
				return 0;
			EditParticle(param1, entity);
				
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	switch(param2)
	{
		case MenuCancel_ExitBack:
		{
			MainEditor(param1);
		}
	}
	return 0;
}