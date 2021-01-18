#include <sourcemod>
// #include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <csgo_colors>

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
	version	 	= "1.0.1",
	url			= "iLoco#7631"
};

/* TODO:
- проверку, не застряла ли модель в стене
- добавить скелет, по кототрому будет двигатся модель
 - заменять на скин игрока
- добавить проверку высоты пола, что бы спавнить на нём, а не в нём
- поддержка вип
- поддерка персонального
- добавить поддержку all в випгруппы
- проверить звук на дальность

ADDED:
	v1.0.1
- добавлена проверка наличия файлов на сервере
- добавлена поддержка партиклов
- фикс опциональности вип-нативов
- добавлен спавн shop-конфига с примером заполнения
- Shop. Добавлена поддержка 'Hide'
- Shop/VIP. Добавлено превью
*/

#define VIP_FEATURE "DanceBomb"
#define TARGET_NAME "DanceBomb"

enum 
{
	NONE = 0,
	EVERYONE = 1,
	SHOP = 2,
	VIP = 4
};

char g_LoadCore[][][] = {{"shop", view_as<int>(SHOP)},
					     {"vip_core", view_as<int>(VIP)}};
int g_IsCoreLoadBits;

float g_iPreviewLastTime[MAXPLAYERS+1];
Handle g_iPreviewTimerHandle[MAXPLAYERS+1];

KeyValues kv, iKv[MAXPLAYERS+1];
ArrayList ar_Priorities;

float g_PreviewTime;

int g_entModel, g_entSprite, g_entParticle;
char g_entSound[256];

Cookie g_VipCookie;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{	
	__pl_shop_SetNTVOptional();
	__pl_vip_core_SetNTVOptional();

	MarkNativeAsOptional("VIP_UnregisterMe");
	
	return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
	Stock_GetCoresLoad(name, true);
}

public void OnLibraryRemoved(const char[] name)
{
	Stock_GetCoresLoad(name, false);
}

stock void Stock_GetCoresLoad(const char[] name, bool isLoad)
{
	for(int c; c < sizeof(g_LoadCore); c++)		if(strcmp(name, g_LoadCore[c][0], false) == 0)
	{
		if(isLoad)
		{
			if(!(g_IsCoreLoadBits & g_LoadCore[c][1][0]))
				g_IsCoreLoadBits |= g_LoadCore[c][1][0];
		}
		else
			g_IsCoreLoadBits &= ~g_LoadCore[c][1][0];

		break;
	}
}

public void OnPluginEnd()
{
	if(g_IsCoreLoadBits & SHOP)
		Shop_UnregisterMe();
	if(g_IsCoreLoadBits & VIP)
		VIP_UnregisterMe();
}

public void OnPluginStart()
{
	for(int c; c < sizeof(g_LoadCore); c++)		if(!(g_IsCoreLoadBits & g_LoadCore[c][1][0]) && LibraryExists(g_LoadCore[c][0]))
		g_IsCoreLoadBits |= g_LoadCore[c][1][0];

	char buffer[256], exp[16][64];

	if(kv)
		delete kv;
	kv = new KeyValues("Dance Bomb");

	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/multi-core/modules/dance_bomb.cfg");
	if(!kv.ImportFromFile(buffer))
		SetFailState("Plugin config '%s' is not finded!", buffer);

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

			ar = new ArrayList(count + 1);
	
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

	for(int i = 1; i <= MaxClients; i++)	if(IsClientAuthorized(i) && IsClientInGame(i))
		OnClientPostAdminCheck(i);

	if(g_IsCoreLoadBits & SHOP && Shop_IsStarted())
		Shop_Started();
	if(g_IsCoreLoadBits & VIP && VIP_IsVIPLoaded())
		VIP_OnVIPLoaded();
}

public void OnMapStart()
{
	kv.Rewind();
	if(!kv.GotoFirstSubKey())
		return;

	char buff[256];
	static int table = INVALID_STRING_TABLE;

	bool save = LockStringTables(false);
	AddToStringTable(FindStringTable("EffectDispatch"), "ParticleEffect");
	LockStringTables(save);
	
	do
	{
		kv.GetString("Model", buff, sizeof(buff));
		if(buff[0] && (FileExists(buff, true) || FileExists(buff, false)))
			PrecacheModel(buff, true);

		kv.GetString("Sprite", buff, sizeof(buff));
		if(buff[0] && (FileExists(buff, true) || FileExists(buff, false)))
			PrecacheDecal(buff, true);

		kv.GetString("Sound", buff, sizeof(buff));
		if(buff[0])
			PrecacheSound(buff, true);

		kv.GetString("Particle file", buff, sizeof(buff));
		if(buff[0] && (FileExists(buff, true) || FileExists(buff, false)))
			PrecacheGeneric(buff, true);

		kv.GetString("Particle name", buff, sizeof(buff));
		if(buff[0])
		{
			if(table == INVALID_STRING_TABLE)
				table = FindStringTable("ParticleEffectNames");

			save = LockStringTables(false);
			AddToStringTable(table, buff);
			LockStringTables(save);
		}
	}
	while(kv.GotoNextKey());
}

public void OnClientPostAdminCheck(int client)
{
	if(iKv[client])
		delete iKv[client];
	iKv[client] = new KeyValues("MyCfg");
	
	char buff[64];

	kv.Rewind();
	kv.GetString("All", buff, sizeof(buff));
	iKv[client].SetString("All", buff);
}

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
		return Plugin_Continue;

	KeyValues kv_sub;
	char buff[256];
	kv.Rewind();

	for(int c; c < ar_Priorities.Length; c++)
	{
		ar_Priorities.GetString(c, buff, sizeof(buff));
		iKv[client].GetString(buff, buff, sizeof(buff));

		if(buff[0] && kv.JumpToKey(buff))
		{
			kv_sub = new KeyValues(buff);
			KvCopySubkeys(kv, kv_sub);
			break;
		}
	}

	if(!kv_sub)
		return Plugin_Continue;
	
	DataPack data = new DataPack();
	data.WriteCell(userid);
	data.WriteCell(EntIndexToEntRef(c4));
	data.WriteCell(kv_sub);

	CreateTimer(kv.GetFloat("delay"), Timer_Delay_CreateBombDance, data, TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
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

stock void Stock_SpawnDanceBomb(int client, int entity = 0, KeyValues kv_sub, bool isPreview)
{
	if(isPreview && !IsPlayerAlive(client))
		return;

	if(client && IsClientInGame(client))
	{
		char buff[256], sound[256];
		int model, sprite, particle;
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
		}

		kv_sub.GetString("Model", buff, sizeof(buff));
		if(buff[0] && (model = CreateEntityByName("prop_dynamic")))
		{ 
			SetEntityModel(model, buff);

			DispatchKeyValue(model, "targetname", TARGET_NAME); 
			SetEntProp(model, Prop_Send, "m_CollisionGroup", 0);
			SetEntProp(model, Prop_Send, "m_nSolidType", 0);
			DispatchKeyValue(model, "solid", (kv_sub.GetNum("Solid Type", 1) == 1 ? "1" : "0"));
				
			SetEntityMoveType(model, MOVETYPE_VPHYSICS);
			
			TeleportEntity(model, origin, NULL_VECTOR, NULL_VECTOR);
			DispatchSpawn(model);
			
			ArrayList ar = view_as<ArrayList>(kv_sub.GetNum("Animations"));
			if(ar)
			{
				ar.GetString(GetRandomInt(0, ar.Length - 1), buff, sizeof(buff));

				SetVariantString(buff);
				AcceptEntityInput(model, "SetAnimation");

				float change_time = kv.GetFloat("Time change");
				if(change_time > 0.0)
				{   
					DataPack data_sec = new DataPack();
					data_sec.WriteCell(g_entModel);
					data_sec.WriteCell(ar);

					CreateTimer(change_time, Timer_ChangeAnim, data_sec, TIMER_REPEAT|TIMER_DATA_HNDL_CLOSE|TIMER_FLAG_NO_MAPCHANGE);
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
				EmitSoundToClient(client, sound, client, SNDCHAN_STATIC, kv_sub.GetNum("Level", 255), _, kv_sub.GetFloat("Volume", 1.0), kv_sub.GetNum("Pitch", 100), _, origin);
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
			g_entParticle = EntIndexToEntRef(particle);
		}
	}

	delete kv_sub;
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

	char sound[256];
	data.ReadString(sound, sizeof(sound));

	Stock_KillEntity(model);
	Stock_KillEntity(sprite);
	Stock_KillEntity(particle);
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

public Action Event_BombExpodeOrDefuse(Event event, char[] name, bool dontBroadcast)
{
	Stock_KillEntity(g_entModel);
	Stock_KillEntity(g_entSprite);
	Stock_KillEntity(g_entParticle);
	Stock_StopSound(0, g_entSound);

	g_entModel = 0;
	g_entSprite = 0;
	g_entParticle = 0;
	g_entSound[0] = '\0';
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


//	Shop Stuff


public void Shop_Started()
{
	KeyValues kv_shop = new KeyValues("Shop Config");

	char buffer[256];
	BuildPath(Path_SM, buffer, sizeof(buffer), "configs/multi-core/settings_shop.cfg");
	if(!kv_shop.ImportFromFile(buffer))
	{
		File file = OpenFile(buffer, "w");
		file.WriteLine("\"Shop Config\"                                                                                                                   ");    							
		file.WriteLine("{                                                                                                                                 ");
		file.WriteLine("//    \"DanceBomb\"        // Идентификатор категории                                                                             ");
		file.WriteLine("//    {                                                                                                                           ");
		file.WriteLine("//        \"Name\"        \"Танцующие бомбы\"        // Имя категории                                                             ");
		file.WriteLine("//                                                                                                                                ");
		file.WriteLine("//        \"Bomb_base\"        // Идентификатор предмета                                                                          ");
		file.WriteLine("//        {                                                                                                                       ");
		file.WriteLine("//            \"Price\"                \"1000\"        // Цена покупки                                                            ");
		file.WriteLine("//            \"Sell Price\"           \"500\"         // Цена продажи                                                            ");
		file.WriteLine("//            \"Duration\"             \"72000\"       // Длительность                                                            ");
		file.WriteLine("//                                                                                                                                ");
		file.WriteLine("//            \"Gold Price\"           \"100\"         // Цена покупки в золоте                                                   ");
		file.WriteLine("//            \"Gold Sell Price\"      \"100\"         // Цена продажи в золоте                                                   ");
		file.WriteLine("//                                                                                                                                ");
		file.WriteLine("//            \"Luck Chance\"          \"100\"         // Шанс выпадения                                                          ");
		file.WriteLine("//            \"Hide\"                 \"0\"           // 1/0 | Скрывать ли его в магазине? (можно выдать только через админку)   ");
		file.WriteLine("//        }                                                                                                                       ");
		file.WriteLine("//    }                                                                                                                           ");
		file.WriteLine("}                                                                                                                                 ");

		LogMessage("Конфиг '%s' был создан, для правильной работы плагина с шопом, настройте его.", buffer);
		
		delete file;
		delete kv_shop;
		return;
	}

	KeyValues kv_sub = new KeyValues("Sub");

	kv.Rewind();
	KvCopySubkeys(kv, kv_sub);

	char category[64], category_name[64], item[64], item_name[64], description[128];
	CategoryId category_id;

	kv_shop.Rewind();
	if(kv_shop.GotoFirstSubKey())
	{
		do
		{
			kv_shop.GetSectionName(category, sizeof(category));
			kv_shop.GetString("Name", category_name, sizeof(category_name));

			kv_shop.SavePosition();
			if(kv_shop.GotoFirstSubKey())
			{
				category_id = Shop_RegisterCategory(category, (category_name[0] ? category_name : category), "");
				do
				{
					kv_shop.GetSectionName(item, sizeof(item));
			
					kv_sub.Rewind();
					if(!kv_sub.JumpToKey(item))
						continue;

					if(!Shop_StartItem(category_id, item))
						continue;

					kv_sub.GetString("Name", item_name, sizeof(item_name));
					kv_sub.GetString("Description", description, sizeof(description));
					
					Shop_SetInfo(item_name, description, kv_shop.GetNum("Price"), kv_shop.GetNum("Sell Price"), Item_Togglable, kv_shop.GetNum("Duration"), kv_shop.GetNum("Gold Price"), kv_shop.GetNum("Gold Sell Price"));
					Shop_SetLuckChance(kv_shop.GetNum("Luck Chance"));
					Shop_SetCallbacks(_, CallBack_Shop_OnItemToggled, .preview = (g_PreviewTime > 0.0 ? CallBack_Shop_OnItemPreview : INVALID_FUNCTION));
					Shop_SetHide(view_as<bool>(kv_shop.GetNum("Hide", 0)));
					Shop_EndItem();
				}
				while(kv_shop.GotoNextKey());
			
				kv_shop.GoBack();
			}
		}
		while(kv_shop.GotoNextKey());
	}

	delete kv_sub;
	delete kv_shop;
}

public void CallBack_Shop_OnItemPreview(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item)
{
	kv.Rewind();
	if(!kv.JumpToKey(item))
		return;

	KeyValues kv_sub = new KeyValues("Sub");
	KvCopySubkeys(kv, kv_sub);

	Stock_SpawnDanceBomb(client, _, kv_sub, true);
}

public ShopAction CallBack_Shop_OnItemToggled(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	if(isOn || elapsed)
	{
		iKv[client].SetString("Shop", "");
		return Shop_UseOff;
	}
		
	iKv[client].SetString("Shop", item);
	return Shop_UseOn;
}


// VIP Stuff


bool g_vip_iPreviewMode[MAXPLAYERS+1];

public void VIP_OnVIPClientLoaded(int client)
{
	if(g_VipCookie)
	{
		char buff[64];
		g_VipCookie.Get(client, buff, sizeof(buff));

		if(buff[0])
			iKv[client].SetString("Vip", buff);
	}
}

public void VIP_OnVIPLoaded()
{
	if(VIP_IsValidFeature(VIP_FEATURE))
		return;

	VIP_RegisterFeature(VIP_FEATURE, STRING, SELECTABLE, CallBack_VIP_OnItemSelected, CallBack_VIP_OnItemDisplayed, .bCookie = true);
	g_VipCookie = Cookie.Find(VIP_FEATURE);
}

public bool CallBack_VIP_OnItemDisplayed(int client, const char[] feature, char[] display, int maxlength)
{
	FormatEx(display, maxlength, "%T", "Menu. VIP. Feature Name", client);
	return true;
}

public bool CallBack_VIP_OnItemSelected(int client, const char[] feature)
{
	g_vip_iPreviewMode[client] = false;
	Menu_VIP_SelectItem(client).Display(client, 0);
	return false;
}

public Menu Menu_VIP_SelectItem(int client)
{
	Menu menu = new Menu(MenuHendler_VIP_SelectItem);
	menu.ExitBackButton = true;

	char myFeature[256];
	VIP_GetClientFeatureString(client, VIP_FEATURE, myFeature, sizeof(myFeature));
	if(!myFeature[0])
		return menu;

	char translate[128], selected_id[64];
	bool iSelectThis;

	Format(translate, sizeof(translate), "%T\n ", "Menu. VIP. Feature Name", client);
	menu.SetTitle(translate);

	g_VipCookie.Get(client, selected_id, sizeof(selected_id));
	iSelectThis = view_as<bool>(selected_id[0]);

	if(g_PreviewTime > 0.0)
	{
		Format(translate, sizeof(translate), "%T", "Menu. VIP. Preview Mode", client);
		Format(translate, sizeof(translate), "%s%T", translate, (g_vip_iPreviewMode[client] ? "Menu. Enable Tag" : "Menu. Disable Tag"), client);
		menu.AddItem("preview", translate);
	}

	Format(translate, sizeof(translate), "%T", "Menu. VIP. Disable", client);
	if(!iSelectThis)
		Format(translate, sizeof(translate), "%s%T", translate, "Menu. VIP. Selected Tag", client);
	Format(translate, sizeof(translate), "%s\n ", translate);
	menu.AddItem("", translate, (!iSelectThis || g_vip_iPreviewMode[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	char exp[64][64];
	int count = ExplodeString(myFeature, ";", exp, sizeof(exp), sizeof(exp[]));

	KeyValues kv_sub = new KeyValues("Sub");
	kv.Rewind();
	KvCopySubkeys(kv, kv_sub);

	for(int c; c < count; c++)
	{
		if(!kv_sub.JumpToKey(exp[c]))
			continue;

		if(g_vip_iPreviewMode[client] && kv.GetFloat("Preview time", g_PreviewTime) <= 0.0)
			continue;
		
		iSelectThis = (strcmp(exp[c], selected_id) == 0);

		kv_sub.GetString("Name", translate, sizeof(translate), exp[c]);
		
		Format(translate, sizeof(translate), "%s", translate);
		if(iSelectThis)
			Format(translate, sizeof(translate), "%s%T", translate, "Menu. VIP. Selected Tag", client);
		menu.AddItem(exp[c], translate, (iSelectThis && !g_vip_iPreviewMode[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

		kv_sub.GoBack();
	}

	if(!menu.ItemCount)
	{
		Format(translate, sizeof(translate), "%T", "Menu. VIP. No Items", client);
		menu.AddItem("", translate, iSelectThis ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	delete kv_sub;
	return menu;
}

public int MenuHendler_VIP_SelectItem(Menu menu, MenuAction action, int client, int item)
{
	if(action == MenuAction_Select)
	{
		char buff[64];
		menu.GetItem(item, buff, sizeof(buff));

		if(strcmp(buff, "preview", false) == 0)
		{
			g_vip_iPreviewMode[client] = !g_vip_iPreviewMode[client];
		}
		else
		{
			if(g_vip_iPreviewMode[client])
			{
				kv.Rewind();
				if(kv.JumpToKey(buff))
				{
					KeyValues kv_sub = new KeyValues("Sub");
					KvCopySubkeys(kv, kv_sub);

					Stock_SpawnDanceBomb(client, _, kv_sub, true);
				}
			}
			else
			{
				g_VipCookie.Set(client, buff);
				iKv[client].SetString("Vip", buff);
			}
		}

		Menu_VIP_SelectItem(client).DisplayAt(client, menu.Selection, 0);
	}
	else if(action == MenuAction_Cancel && item == MenuCancel_ExitBack) 
		VIP_SendClientVIPMenu(client);
	else if(action == MenuAction_End) 
		delete menu;
}