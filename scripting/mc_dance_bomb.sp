#include <sourcemod>
// #include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <mc_core>
// #include <csgo_colors>

#undef REQUIRE_PLUGIN
#tryinclude <shop>
#tryinclude <vip_core>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name		= "[Multi-Core] Dance Bomb",
	author	  	= "iLoco",
	description = "",
	version	 	= "1.0.3",
	url			= "iLoco#7631"
};

/* TODO:
- проверку, не застряла ли модель в стене
- добавить проверку высоты пола, что бы спавнить на нём, а не в нём
- поддерка персонального
- поддержка контроллера
- поддержка LR
- проверить смену анимаций, так-же после того, как кончится предыдущая

ADDED:
	v1.0.1
- добавлена проверка наличия файлов на сервере
- добавлена поддержка партиклов
- фикс опциональности вип-нативов
- добавлен спавн shop-конфига с примером заполнения
- Shop. Добавлена поддержка 'Hide'
- Shop/VIP. Добавлено превью

	v1.0.2
- добавлена функция повтора анимации при её завершении
- добавлена поддержка "скелетной анимации" (Dance bones), аналогия Fortnite Emotes
- фикс размера буфера, из-за этого обрезались названия анимаций и они не работали
- добавлена поддержка {player} в "Model", она заменится на скин игрока
- фикс "Solid Type", он работал наоборот
- фикс проверки "Preview time" в вип меню и регистрации шопа
- VIP. Добавлена поддержка "all" в group.ini для доступа ко всем моделям
<написать что бы кидали предложения>

	v1.0.3
- натив Shop_SetHide добавлен в список опциональных
- добавлена поддержка ядра Multi-Core
*/

#define PLUGIN_ID "DanceBomb"
#define TARGET_NAME "DanceBomb"
#define TARGET_NAME_DANCE "DanceBombEmote"

float g_iPreviewLastTime[MAXPLAYERS+1];
Handle g_iPreviewTimerHandle[MAXPLAYERS+1];

KeyValues kv, iKv[MAXPLAYERS+1];
ArrayList ar_Priorities;

float g_PreviewTime;

int g_entModel, g_entSprite, g_entParticle, g_entEmote;
char g_entSound[256];
ArrayList ar_entEmotes;

#include "multi_core/dance_bomb/shop.inc"
#include "multi_core/dance_bomb/vip.inc"
#include "multi_core/dance_bomb/entity_work.inc"
#include "multi_core/dance_bomb/events.inc"

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{	
	__pl_shop_SetNTVOptional();
	__pl_vip_core_SetNTVOptional();

	MarkNativeAsOptional("VIP_UnregisterMe");
	MarkNativeAsOptional("Shop_SetHide");

	return APLRes_Success;
}

public void OnPluginEnd()
{
	if(MC_IsCoreLoaded(Core_Shop))
		Shop_UnregisterMe();

	if(MC_IsCoreLoaded(Core_VIP))
		VIP_UnregisterMe();
}

public void OnPluginStart()
{
	char buffer[128], exp[16][64];

	kv = MC_GetModuleConfigKV("dance_bomb", "DanceBomb.cfg");

	kv.GetString("Priorities", buffer, sizeof(buffer));
	int count = ExplodeString(buffer, ";", exp, sizeof(exp), sizeof(exp[]));

	g_PreviewTime = kv.GetFloat("Preview time", 5.0);

	ar_Priorities = new ArrayList(count+1);
	for(int c; c < count; c++)  if(exp[c][0])
		ar_Priorities.PushString(exp[c]);

	kv.Rewind();
	if(kv.GotoFirstSubKey())
	{
		ArrayList ar;
		do
		{
			kv.GetString("Animations", buffer, sizeof(buffer));

			if(!buffer[0])
				continue;
			
			count = ExplodeString(buffer, ";", exp, sizeof(exp), sizeof(exp[])) - 1;

			ar = new ArrayList(32);
	
			for(int c; c <= count; c++)  if(exp[c][0])
				ar.PushString(exp[c]); 

			kv.SetNum("Animations", view_as<int>(ar));
		}
		while(kv.GotoNextKey());
	}

	HookEvent("bomb_planted", Event_BombPlanted);
	HookEvent("bomb_exploded", Event_BombExpodeOrDefuse);
	HookEvent("bomb_defused", Event_BombExpodeOrDefuse);
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

	LoadTranslations("mc_dance_bomb.phrases");

	bool isVipLoad = (MC_IsCoreLoaded(Core_VIP) && VIP_IsVIPLoaded());

	if(MC_IsCoreLoaded(Core_Shop) && Shop_IsStarted())
		Shop_Started();
	if(isVipLoad)
		VIP_OnVIPLoaded();

	for(int i = 1; i <= MaxClients; i++)	if(IsClientAuthorized(i) && IsClientInGame(i) && !IsFakeClient(i))
	{
		OnClientPostAdminCheck(i);
		
		if(isVipLoad)
			VIP_OnVIPClientLoaded(i);
	}
}

public void OnMapStart()
{
	kv.Rewind();
	if(!kv.GotoFirstSubKey())
		return;

	do
	{
		MC_PrecacheFile(kv, "Model", Type_Model);
		MC_PrecacheFile(kv, "Dance bones", Type_Model);
		MC_PrecacheFile(kv, "Sound", Type_Sound);
		MC_PrecacheFile(kv, "Sprite", Type_Sprite);
		MC_PrecacheFile(kv, "Particle name", Type_Particle);
		MC_PrecacheFile(kv, "Particle file", Type_ParticleFile);
	}
	while(kv.GotoNextKey());
}

public void OnClientPostAdminCheck(int client)
{
	if(IsFakeClient(client))
		return;

	if(iKv[client])
		delete iKv[client];
	iKv[client] = new KeyValues("MyCfg");
	
	char buff[64];

	kv.Rewind();
	kv.GetString("All", buff, sizeof(buff));
	iKv[client].SetString("All", buff);
}

KeyValues GetSubKV(char[] name = "sub", bool rewind = false, KeyValues from_kv)
{
    if(rewind)
        from_kv.Rewind();

    KeyValues kv_sub = new KeyValues(name);
    KvCopySubkeys(from_kv, kv_sub);

    return kv_sub;
}
