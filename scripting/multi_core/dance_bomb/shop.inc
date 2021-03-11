#include <sourcemod>

public void Shop_Started()
{
	KeyValues kv_shop = MC_GetSettingsConfigKV(Core_Shop);
	KeyValues kv_sub = GetSubKV(_, true);

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
					Shop_SetCallbacks(_, CallBack_Shop_OnItemToggled, .preview = (kv_sub.GetFloat("Preview time", g_PreviewTime) > 0.0 ? CallBack_Shop_OnItemPreview : INVALID_FUNCTION));
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
	Stock_Preview(client, item);
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

