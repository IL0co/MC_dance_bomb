#include <sourcemod>

public Action Event_BombPlanted(Event event, char[] name, bool dontBroadcast)
{
	int c4 = FindEntityByClassname(MaxClients+1, "planted_c4");
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if(client <= 0 || c4 <= 0)
		return;

	char item[64];
	g_kvMain.Rewind();

	if(MC_GetClientActiveItem(client, g_PluginId, item, sizeof(item)))
	{
        DataPack data = new DataPack();
        data.WriteCell(userid);
        data.WriteCell(EntIndexToEntRef(c4));
        data.WriteCell(GetSubKV(item));

        CreateTimer(g_kvMain.GetFloat("delay"), Timer_Delay_CreateBombDance, data, TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);

        return;
	}
}

public Action Timer_Delay_CreateBombDance(Handle timer, DataPack data)
{
	data.Reset();
	int client = data.ReadCell();
	int c4 = EntRefToEntIndex(data.ReadCell());

	if(IsValidEdict(c4))
		Stock_SpawnDanceBomb(GetClientOfUserId(client), c4, data.ReadCell(), false);

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
