#include <sourcemod>

bool g_vip_iPreviewMode[MAXPLAYERS+1];
Cookie g_VipCookie;

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
	if(VIP_IsValidFeature(PLUGIN_ID))
		return;

	VIP_RegisterFeature(PLUGIN_ID, STRING, SELECTABLE, CallBack_VIP_OnItemSelected, CallBack_VIP_OnItemDisplayed, .bCookie = true);
	g_VipCookie = Cookie.Find(PLUGIN_ID);
}

public bool CallBack_VIP_OnItemDisplayed(int client, const char[] feature, char[] display, int maxlength)
{
	FormatEx(display, maxlength, "%T", "Menu. Plugin Id", client);
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
	Menu menu = new Menu(MenuHandler_VIP_SelectItem);
	menu.ExitBackButton = true;

	char myFeature[256];
	VIP_GetClientFeatureString(client, PLUGIN_ID, myFeature, sizeof(myFeature));
	if(!myFeature[0])
		return menu;

	char translate[128], selected_id[64];
	bool iSelectThis;

	Format(translate, sizeof(translate), "%T\n ", "Menu. Plugin Id", client);
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

	bool isAllMode = (strcmp(myFeature, "all", false) == 0);
	
	KeyValues kv_sub = GetSubKV(_, true);

	if(isAllMode)
	{
		kv_sub.Rewind();
		if(kv_sub.GotoFirstSubKey())
		{
			char buff[64];

			do
			{
				kv_sub.GetSectionName(buff, sizeof(buff));
		
				if(g_vip_iPreviewMode[client] && kv_sub.GetFloat("Preview time", g_PreviewTime) <= 0.0)
					continue;
				
				iSelectThis = (strcmp(buff, selected_id) == 0);

				kv_sub.GetString("Name", translate, sizeof(translate), buff);
				
				Format(translate, sizeof(translate), "%s", translate);
				if(iSelectThis)
					Format(translate, sizeof(translate), "%s%T", translate, "Menu. VIP. Selected Tag", client);
				menu.AddItem(buff, translate, (iSelectThis && !g_vip_iPreviewMode[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

				kv_sub.GoBack();
			}
			while(kv_sub.GotoNextKey());
		}
	}
	else
	{
		char exp[64][64];
		int count = ExplodeString(myFeature, ";", exp, sizeof(exp), sizeof(exp[]));

		for(int c; c < count; c++)
		{
			if(!kv_sub.JumpToKey(exp[c]))
				continue;

			if(g_vip_iPreviewMode[client] && kv_sub.GetFloat("Preview time", g_PreviewTime) <= 0.0)
				continue;
			
			iSelectThis = (strcmp(exp[c], selected_id) == 0);

			kv_sub.GetString("Name", translate, sizeof(translate), exp[c]);
			
			Format(translate, sizeof(translate), "%s", translate);
			if(iSelectThis)
				Format(translate, sizeof(translate), "%s%T", translate, "Menu. VIP. Selected Tag", client);
			menu.AddItem(exp[c], translate, (iSelectThis && !g_vip_iPreviewMode[client]) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

			kv_sub.GoBack();
		}
	}

	if(!menu.ItemCount)
	{
		Format(translate, sizeof(translate), "%T", "Menu. VIP. No Items", client);
		menu.AddItem("", translate, iSelectThis ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	delete kv_sub;
	return menu;
}

public int MenuHandler_VIP_SelectItem(Menu menu, MenuAction action, int client, int item)
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
				Stock_Preview(client, buff);
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
