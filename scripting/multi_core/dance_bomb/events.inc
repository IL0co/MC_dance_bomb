#include <sourcemod>

public Action Event_PlayerDisconnect(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(iKv[client])
		delete iKv[client];
}

public Action Event_BombPlanted(Event event, char[] name, bool dontBroadcast)
{
	int c4 = FindEntityByClassname(MaxClients+1, "planted_c4");
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if(client <= 0 || c4 <= 0 || !iKv[client])
		return;

	char buff[256];
	kv.Rewind();

	for(int c; c < ar_Priorities.Length; c++)
	{
		ar_Priorities.GetString(c, buff, sizeof(buff));
		iKv[client].GetString(buff, buff, sizeof(buff));

		if(!buff[0] || !kv.JumpToKey(buff))
            continue;

        DataPack data = new DataPack();
        data.WriteCell(userid);
        data.WriteCell(EntIndexToEntRef(c4));
        data.WriteCell(GetSubKV(buff));

        CreateTimer(kv.GetFloat("delay"), Timer_Delay_CreateBombDance, data, TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);

        return;
	}
}

public Action Timer_Delay_CreateBombDance(Handle timer, DataPack data)
{
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	int c4 = EntRefToEntIndex(data.ReadCell());
	KeyValues kv_sub = data.ReadCell();

	if(!IsValidEdict(c4))
		return Plugin_Stop;

	float bomb_origin[3];
	GetEntPropVector(c4, Prop_Send, "m_vecOrigin", bomb_origin, 0);

	Stock_SpawnDanceBomb(client, c4, kv_sub, false);

	return Plugin_Stop;
}

public Action Event_BombExpodeOrDefuse(Event event, char[] name, bool dontBroadcast)
{
	Stock_KillEntity(g_entModel);
	Stock_KillEntity(g_entSprite);
	Stock_KillEntity(g_entParticle);
	Stock_KillEntity(g_entEmote);
	Stock_StopSound(0, g_entSound);

	g_entModel = 0;
	g_entSprite = 0;
	g_entParticle = 0;
	g_entEmote = 0;
	g_entSound[0] = '\0';
}
