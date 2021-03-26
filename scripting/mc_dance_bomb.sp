#include <sourcemod>
// #include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <mc_core>
// #include <csgo_colors>

#undef REQUIRE_PLUGIN
// #tryinclude <shop>
// #tryinclude <vip_core>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name		= "[Multi-Core] Dance Bomb",
	author	  	= "iLoco",
	description = "",
	version	 	= "1.0.3.2",
	url			= "iLoco#7631"
};

/* TODO:
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
- добавлена проверка на застревание
- добавлена телепортация к полу
*/

#define PLUGIN_ID "DanceBomb"
#define TARGET_NAME "DanceBomb"
#define TARGET_NAME_DANCE "DanceBombEmote"

float g_fPreviewLastTime[MAXPLAYERS+1];
Handle g_hPreviewTimerHandle[MAXPLAYERS+1];

KeyValues g_kvMain;
PluginId g_PluginId;

float g_PreviewTime;
int g_iMaxTrying;

int g_entModel, g_entSprite, g_entParticle, g_entEmote;
char g_entSound[256];
ArrayList ar_entEmotes;

#include "multi_core/dance_bomb/entity_work.inc"
#include "multi_core/dance_bomb/events.inc"

public void OnPluginEnd()
{
	MC_UnRegisterMe();
}

public void OnPluginStart()
{
	char buffer[128], exp[16][64];
	int count;

	g_kvMain = MC_GetModuleConfigKV("dance_bomb.cfg", "Dance Bomb");

	g_PreviewTime = g_kvMain.GetFloat("Preview time", 5.0);
	g_iMaxTrying = g_kvMain.GetNum("Max Trying", 1);

	g_kvMain.Rewind();
	if(g_kvMain.GotoFirstSubKey())
	{
		ArrayList ar;
		do
		{
			g_kvMain.GetString("Animations", buffer, sizeof(buffer));

			if(!buffer[0])
				continue;
			
			count = ExplodeString(buffer, ";", exp, sizeof(exp), sizeof(exp[])) - 1;

			ar = new ArrayList(32);
	
			for(int c; c <= count; c++)  if(exp[c][0])
				ar.PushString(exp[c]); 

			g_kvMain.SetNum("Animations", view_as<int>(ar));
		}
		while(g_kvMain.GotoNextKey());
	}

	HookEvent("bomb_planted", Event_BombPlanted);
	HookEvent("bomb_exploded", Event_BombExpodeOrDefuse, EventHookMode_Pre);
	HookEvent("bomb_defused", Event_BombExpodeOrDefuse, EventHookMode_Pre);

	LoadTranslations("mc_dance_bomb.phrases");

	if(MC_IsCoreLoaded(Core_MultiCore))
		MC_OnCoreChangeStatus("", Core_MultiCore, true);
}

public void MC_OnCoreChangeStatus(char[] core_name, MC_CoreTypeBits core_type, bool isLoaded)
{
	if(!isLoaded || core_type != Core_MultiCore)
		return;

	MC_RegisterPlugin(PLUGIN_ID, CallBack_OnCategoryDisplay);

	char buffer[256];
	g_kvMain.Rewind();

	if(g_kvMain.GotoFirstSubKey())
	{
		do
		{
			g_kvMain.GetSectionName(buffer, sizeof(buffer));

			if(!MC_StartItem(buffer))
				continue;
			
			MC_SetItemCallBacks(CallBack_OnItemDisplay, CallBack_OnItemPreview);
			MC_EndItem();
		}
		while(g_kvMain.GotoNextKey());
	}

	g_PluginId = MC_EndPlugin();
}

public bool CallBack_OnCategoryDisplay(int client, const char[] plugin_unique, PluginId plugin_id, MC_CoreTypeBits core_type, char[] buffer, int maxlen)
{
	FormatEx(buffer, maxlen, "%T", "Menu. Plugin Id", client);
	return true;
}

public bool CallBack_OnItemDisplay(int client, const char[] plugin_unique, PluginId plugin_id, const char[] item_unique, MC_CoreTypeBits core_type, char[] buffer, int maxlen)
{
	g_kvMain.Rewind();

	if(!g_kvMain.JumpToKey(item_unique))
		return false;

	g_kvMain.GetString("Name", buffer, maxlen, item_unique);
	return true;
}

public void CallBack_OnItemPreview(int client, const char[] plugin_unique, PluginId plugin_id, const char[] item_unique, MC_CoreTypeBits core_type)
{
	Stock_Preview(client, item_unique);
}

public void OnMapStart()
{
	g_kvMain.Rewind();
	if(!g_kvMain.GotoFirstSubKey())
		return;
		
	char file[256];

	do
	{
		g_kvMain.GetString("Model", file, sizeof(file));
		if(file[0])
			MC_PrecacheFile(file, Type_Model);
			
		g_kvMain.GetString("Dance bones", file, sizeof(file));
		if(file[0])
			MC_PrecacheFile(file, Type_Model);

		g_kvMain.GetString("Sound", file, sizeof(file));
		if(file[0])
			MC_PrecacheFile(file, Type_Sound);

		g_kvMain.GetString("Sprite", file, sizeof(file));
		if(file[0])
			MC_PrecacheFile(file, Type_Sprite);

		g_kvMain.GetString("Particle name", file, sizeof(file));
		if(file[0])
			MC_PrecacheFile(file, Type_Particle);

		g_kvMain.GetString("Particle file", file, sizeof(file));
		if(file[0])
			MC_PrecacheFile(file, Type_ParticleFile);
	}
	while(g_kvMain.GotoNextKey());
}

KeyValues GetSubKV(char[] name = "sub", bool rewind = false)
{
    if(rewind)
        g_kvMain.Rewind();

    KeyValues kv_sub = new KeyValues(name);
    KvCopySubkeys(g_kvMain, kv_sub);

    return kv_sub;
}
