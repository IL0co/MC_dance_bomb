#include <sourcemod>

stock void Stock_SpawnDanceBomb(int client, int entity = 0, KeyValues kv_sub, bool isPreview)
{
	if(isPreview && !IsPlayerAlive(client))
		return;

	if(client && IsClientInGame(client))
	{
		char buff[256], sound[256];
		int model, sprite, particle, emote;
		float origin[3];

		if(isPreview)
		{
			float ang[3], pos[3];
		
			GetClientEyePosition(client, pos);
			GetClientEyeAngles(client, ang);

			TR_TraceRayFilter(pos, ang, MASK_SOLID, RayType_Infinite, TraceRayFilter_NoPlayers);
			TR_GetEndPosition(origin);
		}
		else
		{
			float vec_offset[3];

			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin, 0);
			kv_sub.GetVector("Pos offset", vec_offset);
			AddVectors(origin, vec_offset, origin);

			ar_entEmotes = null;
		}

		kv_sub.GetString("Model", buff, sizeof(buff));
		if(buff[0] && (model = CreateEntityByName("prop_dynamic_override")))
		{ 
			if(strcmp(buff, "{player}", false) == 0)
				GetClientModel(client, buff, sizeof(buff));

			SetEntityModel(model, buff);

			DispatchKeyValue(model, "targetname", TARGET_NAME); 
			SetEntProp(model, Prop_Send, "m_CollisionGroup", 0);
			SetEntProp(model, Prop_Send, "m_nSolidType", 0);
			DispatchKeyValue(model, "solid", (kv_sub.GetNum("Solid Type", 1) == 1 ? "0" : "1"));
				
			SetEntityMoveType(model, MOVETYPE_VPHYSICS);
			
			TeleportEntity(model, origin, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(model);

			kv_sub.GetString("Dance bones", buff, sizeof(buff));
			if(buff[0] && (emote = CreateEntityByName("prop_dynamic_override")))
			{
				DispatchKeyValue(emote, "model", buff);

				DispatchKeyValue(emote, "targetname", TARGET_NAME_DANCE);
				DispatchKeyValue(emote, "solid", "0");

				ActivateEntity(emote);
				DispatchSpawn(emote);

				TeleportEntity(emote, origin, NULL_VECTOR, NULL_VECTOR);
				
				SetEntProp(model, Prop_Send, "m_fEffects", (1 << 0)|(1 << 4)|(1 << 6)|(1 << 9)|128);
				
				SetVariantString("!activator");
				AcceptEntityInput(model, "SetParent", emote, model, 0);

				SetVariantString("primary");
				AcceptEntityInput(model, "SetParentAttachment", model, model, 0);
			}
			
			ArrayList ar = view_as<ArrayList>(kv_sub.GetNum("Animations"));
			if(ar)
			{
				ar.GetString(GetRandomInt(0, ar.Length - 1), buff, sizeof(buff));

				SetVariantString(buff);
				AcceptEntityInput(emote ? emote : model, "SetAnimation", -1, -1, 0);

				float change_time = kv.GetFloat("Time change");
				if(change_time > 0.0)
				{   
					DataPack data_sec = new DataPack();
					data_sec.WriteCell(emote ? emote : model);
					data_sec.WriteCell(ar);

					CreateTimer(change_time, Timer_ChangeAnim, data_sec, TIMER_REPEAT|TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);
				}
				else if(change_time == -1.0 && !isPreview)
				{
					ar_entEmotes = ar;
					HookSingleEntityOutput(emote ? emote : model, "OnAnimationDone", EndOutput_OnAnimationDone, true);
				}
			}
		}

		kv_sub.GetString("Sprite", buff, sizeof(buff));
		if(buff[0] && (sprite = CreateEntityByName("env_sprite")))
		{ 
			DispatchKeyValue(sprite, "spawnflags", "1");
			DispatchKeyValueFloat(sprite, "scale", 0.5);
			DispatchKeyValue(sprite, "rendermode", "1");
			DispatchKeyValue(sprite, "rendercolor", "255 255 255");
			DispatchKeyValue(sprite, "model", buff); 
			DispatchKeyValue(sprite, "targetname", TARGET_NAME); 
			DispatchSpawn(sprite);

			TeleportEntity(sprite, origin, NULL_VECTOR, NULL_VECTOR);
		}

		kv_sub.GetString("Sound", sound, sizeof(sound));
		if(sound[0])
		{
			if(isPreview)
				EmitSoundToClient(client, sound, client, SNDCHAN_STATIC, kv_sub.GetNum("Level", 255), _, kv_sub.GetFloat("Volume", 1.0), kv_sub.GetNum("Pitch", 100), _, origin, origin);
			else
				EmitSoundToAll(sound, 0, SNDCHAN_STATIC, kv_sub.GetNum("Level", 255), _, kv_sub.GetFloat("Volume", 1.0), kv_sub.GetNum("Pitch", 100), _, origin);
		}

		kv_sub.GetString("Particle name", buff, sizeof(buff));
		if(buff[0] && (particle = CreateEntityByName("info_particle_system")))
		{
			DispatchKeyValue(particle, "targetname", TARGET_NAME);
			DispatchKeyValue(particle, "effect_name", buff);
			DispatchSpawn(particle);
			DispatchKeyValue(particle, "start_active", "1");
			ActivateEntity(particle);
			AcceptEntityInput(particle, "Start");
			TeleportEntity(particle, origin, NULL_VECTOR, NULL_VECTOR);
			SetVariantString("!activator");
		}

		if(isPreview)
		{
			if(model)
			{
				SetEntPropEnt(model, Prop_Send, "m_hOwnerEntity", client);
				SDKHook(model, SDKHook_SetTransmit, Hook_SetTransmit);
			}
			if(sprite)
			{
				SetEntPropEnt(sprite, Prop_Send, "m_hOwnerEntity", client);
				SDKHook(sprite, SDKHook_SetTransmit, Hook_SetTransmit);
			}
			if(particle)
			{
				SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", client);
				SDKHook(particle, SDKHook_SetTransmit, Hook_SetTransmit_Particle);
			}
			
			DataPack data = new DataPack();
			data.WriteCell(GetClientUserId(client));
			data.WriteCell(EntIndexToEntRef(model));
			data.WriteCell(EntIndexToEntRef(sprite));
			data.WriteCell(EntIndexToEntRef(emote));
			data.WriteCell(EntIndexToEntRef(particle));
			data.WriteString(sound);

			g_iPreviewLastTime[client] = kv_sub.GetFloat("Preview time", g_PreviewTime);
			g_iPreviewTimerHandle[client] = CreateTimer(0.1, Timer_Preview, data, TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		}
		else
		{
			Format(g_entSound, sizeof(g_entSound), sound);
			g_entModel = EntIndexToEntRef(model);
			g_entSprite = EntIndexToEntRef(sprite);
			g_entEmote = EntIndexToEntRef(emote);
			g_entParticle = EntIndexToEntRef(particle);
		}
	}

	delete kv_sub;
}

public void EndOutput_OnAnimationDone(const char[] output, int caller, int activator, float delay) 
{
	if(ar_entEmotes && caller && IsValidEdict(caller))
	{
		char buff[64];
		ar_entEmotes.GetString(GetRandomInt(0, ar_entEmotes.Length - 1), buff, sizeof(buff));

		SetVariantString(buff);
		AcceptEntityInput(caller, "SetAnimation", -1, -1, 0);
	}
}

public Action Timer_Preview(Handle timer, DataPack data)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());

	PrintHintText(client, "%T", "Hint. Draw Preview Time", client, g_iPreviewLastTime[client]);

	if((g_iPreviewLastTime[client] -= 0.1) > 0.0 && g_iPreviewTimerHandle[client] == timer && client > 0 && client <= MaxClients && IsPlayerAlive(client) && IsClientInGame(client))
		return Plugin_Continue; 

	int model = data.ReadCell();
	int sprite = data.ReadCell();
	int particle = data.ReadCell();
	int emote = data.ReadCell();

	char sound[256];
	data.ReadString(sound, sizeof(sound));

	Stock_KillEntity(model);
	Stock_KillEntity(sprite);
	Stock_KillEntity(particle);
	Stock_KillEntity(emote);
	Stock_StopSound(client, sound);

	return Plugin_Stop;
}

public Action Hook_SetTransmit_Particle(int ent, int client)
{
	if(!Stock_Transmit_IsClientOwner(ent, client, false))
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action Hook_SetTransmit(int ent, int client)
{
	if(!Stock_Transmit_IsClientOwner(ent, client, false))
		return Plugin_Handled;

	return Plugin_Continue;
}

stock bool Stock_Transmit_IsClientOwner(int ent, int client, bool isParticle = false)
{
	static int owner;

	if(!ent || !client)
		return false;

	if(isParticle && GetEdictFlags(ent) & FL_EDICT_ALWAYS)
	 	SetEdictFlags(ent, (GetEdictFlags(ent) ^ FL_EDICT_ALWAYS));

	if((owner = GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity")) == -1)
		owner = 0;

	if(client == owner)
		return true;

	return false;
}

public bool TraceRayFilter_NoPlayers(int ent, int mask)
{
	if(ent > MaxClients)
		return true;

	return false;
}

public Action Timer_ChangeAnim(Handle timer, DataPack data)
{
	data.Reset();

	int ent = EntRefToEntIndex(data.ReadCell());

	if(!IsValidEntity(ent))
		return Plugin_Stop;

	char buff[64];
	ArrayList ar = data.ReadCell();

	ar.GetString(GetRandomInt(0, ar_Priorities.Length - 1), buff, sizeof(buff));
	SetVariantString(buff);
	AcceptEntityInput(ent, "SetAnimation");

	return Plugin_Continue;
}

stock void Stock_KillEntity(int ent_ref)
{
	int ent = EntRefToEntIndex(ent_ref);
	if(IsValidEntity(ent) && ent > 0 && ent < 2048)
		AcceptEntityInput(ent, "kill");
}

stock void Stock_StopSound(int ent = 0, char[] sound_file)
{
	if(sound_file[0])	
		StopSound(ent, SNDCHAN_STATIC, sound_file);
}

stock void Stock_Preview(int client, const char[] item)
{
	kv.Rewind();
	if(!kv.JumpToKey(item))
		return;

	Stock_SpawnDanceBomb(client, _, GetSubKV(), true);
}
