// check classify during view
// seeing 0 views icon with nobody viewing

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

array<PlayerDat> g_playerdat;
array<ViewDat> g_viewents;

string screenlook_spr = "screenlook.spr";
string eye_spr = "sprites/screenlook2.spr";

// Menus need to be defined globally when the plugin is loaded or else paging doesn't work.
// Each player needs their own menu or else paging breaks when someone else opens the menu.
// These also need to be modified directly (not via a local var reference).
array<CTextMenu@> g_menus(g_Engine.maxClients+1, null);

void PluginInit()
{	
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy/" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientDisconnect);
	
	g_viewents.resize(33);
	g_playerdat.resize(33);
	
	g_Scheduler.SetInterval("view_counter_loop", 0.2f, -1);
}

void PluginExit()
{
	for (uint i = 0; i < g_viewents.size(); i++) {
		g_viewents[i].Remove();
	}
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		g_EngineFuncs.SetView(plr.edict(), plr.edict());
	}
}

void MapInit() {	
	g_viewents.resize(0);
	g_viewents.resize(33);
	
	g_playerdat.resize(0);
	g_playerdat.resize(33);
	
	g_Game.PrecacheGeneric("sprites/" + screenlook_spr);
	g_Game.PrecacheModel(eye_spr);
}

HookReturnCode ClientDisconnect(CBasePlayer@ pPlayer) {
	g_playerdat[pPlayer.entindex()].lastViewTarget = "";
    return HOOK_CONTINUE;
}

class PlayerDat {
	int lastSpecCount;
	int specCount;
	string lastViewTarget; // for toggling
	float lastViewCommand;
	float lastObserverCommand;
	bool wantsSpectate; // keep observers dead
	array<float> lastNotify; // last time viewer notification was sent from each player
	
	PlayerDat() {
		lastNotify.resize(33);
	}
}

class ViewAttachment {
	EHandle h_hat;
	EHandle h_render;
	
	ViewAttachment() {}
	
	ViewAttachment(EHandle h_hat, EHandle h_render) {
		this.h_hat = h_hat;
		this.h_render = h_render;
	}
}

class ViewDat {
	int targetidx = -1;
	EHandle h_viewer;
	EHandle h_cam;
	EHandle h_weapon;
	EHandle h_plr_render;
	EHandle h_wep_render;
	EHandle h_icon;
	float lastFrame;
	int lastClip;
	int lastWepIdx;
	bool lastInReload;
	int lastAnim;
	int lastPlrButtons;
	bool isGauss;
	float lastHudUpdate;
	float lastHudSprUpdate;
	bool wasDead;
	float lastHatHide;
	array<ViewAttachment> viewhats;
	
	ViewDat() {}
	
	ViewDat(EHandle h_cam, EHandle h_viewer, int targetidx, EHandle h_weapon, EHandle h_plr_render, EHandle h_wep_render, EHandle h_icon) {
		this.h_cam = h_cam;
		this.h_viewer = h_viewer;
		this.targetidx = targetidx;
		this.h_weapon = h_weapon;
		this.h_plr_render = h_plr_render;
		this.h_wep_render = h_wep_render;
		this.h_icon = h_icon;
	}
	
	bool isViewing() {
		return h_viewer.IsValid();
	}
	
	void hideAttachments() {
		CBasePlayer@ viewer = cast<CBasePlayer@>(h_viewer.GetEntity());
		CBasePlayer@ actor = g_PlayerFuncs.FindPlayerByIndex(targetidx);
		
		if (viewer is null || actor is null) {
			return;
		}
		
		array<CBaseEntity@> newAttach;
		
		{
			CBaseEntity@ ent = null;
			do {
				@ent = g_EntityFuncs.FindEntityByClassname(ent, "info_target"); 
				if (ent !is null)
				{
					if (@ent.pev.aiment == @actor.edict()) {
						newAttach.insertLast(ent);
					}
				}
			} while (ent !is null);
		}
		
		bool attachmentsChanged = newAttach.size() != viewhats.size();
		
		if (!attachmentsChanged) {
			for (uint i = 0; i < newAttach.size(); i++) {
				int searchIdx = newAttach[i].entindex();
				bool matched = false;
				
				for (uint k = 0; k < viewhats.size(); k++) {
					CBaseEntity@ hat = viewhats[k].h_hat;
					if (hat is null) {
						break;
					}
					if (hat.entindex() == searchIdx) {
						matched = true;
						break;
					}
				}
				
				if (!matched) {
					attachmentsChanged = true;
					break;
				}
			}
		}
		
		if (attachmentsChanged) {
			for (uint i = 0; i < viewhats.size(); i++) {
				g_EntityFuncs.Remove(viewhats[i].h_render);
			}
			viewhats.resize(0);
		
			for (uint i = 0; i < newAttach.size(); i++) {
				CBaseEntity@ ent = @newAttach[i];
				
				string tname = "as_view_hat_hide" + viewer.entindex();
				CBaseEntity@ attachHide = g_EntityFuncs.CreateEntity("env_render_individual", {
					{'target', tname},
					{'targetname', "as_view_render_" + viewer.entindex()},
					{'spawnflags', "" + (1 | 8 | 64)}, // no renderfx + no rendercolor + affect activator
					{'rendermode', "1"},
					{'renderamt', "0"}
				}, true);
				
				string oldName = ent.pev.targetname;
				ent.pev.targetname = tname;
				attachHide.Use(viewer, viewer, USE_ON);
				ent.pev.targetname = oldName;
				
				viewhats.insertLast( ViewAttachment(EHandle(ent), EHandle(attachHide)) );
			}
		}
	}
	
	void Remove() {
		g_EntityFuncs.Remove(h_cam);
		g_EntityFuncs.Remove(h_weapon);
		g_EntityFuncs.Remove(h_plr_render);
		g_EntityFuncs.Remove(h_wep_render);
		g_EntityFuncs.Remove(h_icon);
		
		for (uint i = 0; i < viewhats.size(); i++) {
			g_EntityFuncs.Remove(viewhats[i].h_render);
		}
		viewhats.resize(0);
		
		lastHudUpdate = 0;
		lastHudSprUpdate = 0;
		
		if (targetidx != -1) {
			g_playerdat[targetidx].specCount -= 1;
			targetidx = -1;
		}
		
		CBasePlayer@ viewer = cast<CBasePlayer@>(h_viewer.GetEntity());
		if (viewer !is null) {
			g_EngineFuncs.SetView(viewer.edict(), viewer.edict());
			clientCommand(viewer, "stopsound");
			h_viewer = null; // prevent double view reset
		}
	}
}

void delay_respawn(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	// the player respawn hooks don't work, so this has to be done to prevent respawning.
	plr.m_flRespawnDelayTime = 100000 - g_EngineFuncs.CVarGetFloat("mp_respawndelay");
}

dictionary weapon_shoot_anims = {
	{'weapon_9mmhandgun', 3},
	{'weapon_eagle', 5},
	{'weapon_uzi', 5},
	{'weapon_uzi_akimbo', 15},
	{'weapon_9mmAR', 5},
	{'weapon_shotgun', 1},
	{'weapon_crossbow', 4},
	{'weapon_m16', 4},
	{'weapon_gauss', 6},
	{'weapon_m249', 6},
	{'weapon_sniperrifle', 2},
	{'weapon_sporelauncher', 5},
	{'weapon_shockrifle', 1},
	{'weapon_medkit', 3},
	{'weapon_hornetgun', 5},
	{'weapon_357', 2}
};

dictionary weapon_reload_anims = {
	{'weapon_9mmhandgun', 6},
	{'weapon_eagle', 7},
	{'weapon_uzi', 3},
	{'weapon_uzi_akimbo', 12},
	{'weapon_9mmAR', 3},
	{'weapon_357', 3}
};

string getWepName(string name, bool isAkimbo) {
	if (isAkimbo && name == "weapon_uzi") {
		return "weapon_uzi_akimbo";	
	}
	return name;
}

void playAnimation(CBaseMonster@ wep, int anim, float startFrame=0, float framerate=1) {
	wep.m_Activity = ACT_RELOAD;
	wep.pev.sequence = anim;
	wep.pev.frame = startFrame;
	wep.ResetSequenceInfo();
	wep.pev.framerate = framerate;
}

// copies the actor's view model animation to another entity.
// some animation details aren't visible to angelscript so all this stupid bullshit logic is needed
void update_weapon_anim(ViewDat@ viewdat, CBasePlayer@ actor, CBasePlayerWeapon@ actorWep, CBaseMonster@ fakeWep) {	
	if (string(fakeWep.pev.model) != actor.pev.viewmodel) {
		g_EntityFuncs.SetModel(fakeWep, actor.pev.viewmodel);
	}
	
	bool weaponSwitched = viewdat.lastWepIdx != actorWep.entindex();
	int primaryAmmo = actorWep.m_iPrimaryAmmoType != -1 ? actor.m_rgAmmo( actorWep.m_iPrimaryAmmoType ) : 0;
	int clip = actorWep.m_iClip == -1 ? primaryAmmo : actorWep.m_iClip;
	bool inWater = actor.pev.waterlevel == 3;
	
	bool secondaryReleased = (actor.m_afButtonPressed & IN_ATTACK2) == 0 && (viewdat.lastPlrButtons & IN_ATTACK2) != 0;
	bool gaussSecondaryShot = viewdat.isGauss && secondaryReleased && !inWater;
	
	if (weaponSwitched) {
		viewdat.isGauss = actorWep.pev.classname == "weapon_gauss";
		viewdat.lastAnim = -1;
	}
	else if ((clip < viewdat.lastClip || gaussSecondaryShot) && !weaponSwitched) {
		// weapon fired
		string cname = getWepName(actorWep.pev.classname, actorWep.m_fIsAkimbo);
		
		bool isGaussCharge = !gaussSecondaryShot && cname == "weapon_gauss" && actor.pev.weaponanim == 4;
	
		if (weapon_shoot_anims.exists(cname) && !isGaussCharge) {
			int anim = -1;
			weapon_shoot_anims.get(cname, anim);
			playAnimation(fakeWep, anim);
		}			
	}
	else if (actorWep.m_fInReload && !viewdat.lastInReload && !weaponSwitched) {
		// weapon reloade
		string cname = getWepName(actorWep.pev.classname, actorWep.m_fIsAkimbo);
		
		if (weapon_reload_anims.exists(cname)) {
			int anim = -1;
			weapon_reload_anims.get(cname, anim);
			playAnimation(fakeWep, anim);
		}			
	}
	else if (viewdat.lastAnim != actor.pev.weaponanim || weaponSwitched) {
		// weapon animation changed
		//println("NEW SEQ " + actor.pev.weaponanim);
		playAnimation(fakeWep, actor.pev.weaponanim);
		viewdat.lastAnim = fakeWep.pev.sequence; // setting lastAnim here so shoot/reload animations aren't interrupted
		
	} else if (fakeWep.pev.frame < viewdat.lastFrame || fakeWep.pev.frame > 250.0f) {
		// animation looped
		string cname = getWepName(actorWep.pev.classname, actorWep.m_fIsAkimbo);
		
		bool isShotgunReload = cname == "weapon_shotgun" && actor.pev.weaponanim == 3;
		bool isGaussCharge = viewdat.isGauss && actor.pev.weaponanim == 4 && (actor.m_afButtonPressed & IN_ATTACK2) != 0;
		bool isSporeLoad = cname == "weapon_sporelauncher" && actor.pev.weaponanim == 3;
		bool isEgonShoot = cname == "weapon_egon" && actor.pev.weaponanim >= 5 && actor.pev.weaponanim <=8;
		
		bool isOkToLoop = isShotgunReload || isGaussCharge || isSporeLoad || isEgonShoot;
		
		if (!isOkToLoop) {
			// freeze on last frame
			playAnimation(fakeWep, actor.pev.weaponanim, 254.9f, 0.000001f);
		}
	}
	
	viewdat.lastFrame = fakeWep.pev.frame;
	viewdat.lastWepIdx = actorWep.entindex();
	viewdat.lastClip = clip;
	viewdat.lastInReload = actorWep.m_fInReload;
	viewdat.lastPlrButtons = actor.m_afButtonPressed;
}

void HudMessageUnreliable(CBasePlayer@ plr, const HUDTextParams& in txtPrms, const string& in text) {
  if (plr is null)
    return;

  NetworkMessage m(MSG_ONE_UNRELIABLE, NetworkMessages::SVC_TEMPENTITY, plr.edict());
    m.WriteByte(TE_TEXTMESSAGE);
    m.WriteByte(txtPrms.channel & 0xFF);

    m.WriteShort(FixedSigned16(txtPrms.x, 1<<13));
    m.WriteShort(FixedSigned16(txtPrms.y, 1<<13));
    m.WriteByte(txtPrms.effect);

    m.WriteByte(txtPrms.r1);
    m.WriteByte(txtPrms.g1);
    m.WriteByte(txtPrms.b1);
    m.WriteByte(txtPrms.a1);

    m.WriteByte(txtPrms.r2);
    m.WriteByte(txtPrms.g2);
    m.WriteByte(txtPrms.b2);
    m.WriteByte(txtPrms.a2);

    m.WriteShort(FixedUnsigned16(txtPrms.fadeinTime, 1<<8));
    m.WriteShort(FixedUnsigned16(txtPrms.fadeoutTime, 1<<8));
    m.WriteShort(FixedUnsigned16(txtPrms.holdTime, 1<<8));

    if (txtPrms.effect == 2) 
      m.WriteShort(FixedUnsigned16(txtPrms.fxTime, 1<<8));

    m.WriteString(text);
  m.End();
}

void view_counter_loop() {
	for ( int i = 1; i <= g_Engine.maxClients; i++ ) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected()) {
			continue;
		}
		
		ViewDat@ viewdat = @g_viewents[i];
		PlayerDat@ playerdat = @g_playerdat[i];
		bool anySpecs = playerdat.lastSpecCount != 0 || playerdat.specCount != 0;
		
		if (plr.IsAlive() && viewdat.wasDead && viewdat.isViewing()) {
			g_EngineFuncs.SetView(plr.edict(), viewdat.h_cam.GetEntity().edict());
			clientCommand(plr, "stopsound");
		}
		
		//println("[SPEC] " + plr.pev.netname + " " + playerdat.specCount + " " + playerdat.lastSpecCount);
		
		if (anySpecs && (viewdat.lastHudSprUpdate + 2.1f < g_Engine.time || playerdat.specCount != playerdat.lastSpecCount)) {
			viewdat.lastHudSprUpdate = g_Engine.time;
			
			HUDSpriteParams spr;
			spr.channel = 1;
			spr.flags = HUD_ELEM_DEFAULT_ALPHA | HUD_ELEM_SCR_CENTER_Y | HUD_ELEM_ABSOLUTE_X;
			spr.spritename = screenlook_spr;
			spr.color1 = RGBA(255, 255, 255, 128);
			spr.color2 = RGBA(255, 255, 255, 128);
			spr.frame = playerdat.specCount;
			spr.fadeinTime = playerdat.specCount == 1 && playerdat.lastSpecCount == 0 ? 0.5f : 0;
			spr.fadeoutTime = 0.5f;
			spr.x = 0;
			spr.y = 0;
			spr.holdTime = playerdat.specCount == 0 ? 1.0f : 2.5f;
			
			HudCustomSpriteMsg(plr.edict(), spr);
		}
		
		playerdat.lastSpecCount = playerdat.specCount;
		viewdat.wasDead = !plr.IsAlive();
		
		if (playerdat.specCount < 0) {
			playerdat.specCount = 0;
		}
	}
}

void view_loop(ViewDat@ viewdat) {
	CBasePlayer@ viewer = cast<CBasePlayer@>(viewdat.h_viewer.GetEntity());
	CBasePlayer@ actor = g_PlayerFuncs.FindPlayerByIndex(viewdat.targetidx);
	CBaseEntity@ infoent = viewdat.h_cam;
	CBaseMonster@ fakeWep = cast<CBaseMonster@>(viewdat.h_weapon.GetEntity());
	
	if (viewer is null || actor is null || !viewer.IsConnected() || !actor.IsConnected() || infoent is null || fakeWep is null) {
		viewdat.Remove();
		//println("Aborted view loop");
		return;
	}
	
	infoent.pev.origin = actor.pev.origin + actor.pev.view_ofs;
	infoent.pev.angles = actor.pev.v_angle;
	
	fakeWep.pev.origin = infoent.pev.origin;
	fakeWep.pev.angles = actor.pev.v_angle;
	fakeWep.pev.angles.x = -fakeWep.pev.angles.x;
	
	viewer.m_iFOV = actor.m_iFOV;
	
	infoent.pev.nextthink = g_Engine.time;
	fakeWep.pev.nextthink = g_Engine.time;
	
	infoent.pev.effects |= EF_NOINTERP;
	fakeWep.pev.effects |= EF_NOINTERP;
	
	CBasePlayerWeapon@ actorWep = cast<CBasePlayerWeapon@>(actor.m_hActiveItem.GetEntity());
	
	if (actorWep !is null) {
		if (viewdat.lastWepIdx == -1)
			viewdat.h_wep_render.GetEntity().Use(viewer, viewer, USE_ON);
		update_weapon_anim(viewdat, actor, actorWep, fakeWep);
	} else {
		if (viewdat.lastWepIdx != -1)
			viewdat.h_wep_render.GetEntity().Use(viewer, viewer, USE_OFF);
		viewdat.lastWepIdx = -1;
	}
	
	if (viewdat.lastHatHide + 2.0f < g_Engine.time) {
		viewdat.lastHatHide = g_Engine.time;
		viewdat.hideAttachments();
	}
	
	if (viewdat.lastHudUpdate + 0.1f < g_Engine.time) {
		viewdat.lastHudUpdate = g_Engine.time;
		
		HUDTextParams txtPrms;

		txtPrms.r1 = 100;
		txtPrms.g1 = 130;
		txtPrms.b1 = 200;
		txtPrms.a1 = 0;

		txtPrms.x = -1.0f;
		txtPrms.y = 1.0f;
		txtPrms.effect = 0;
		txtPrms.fadeinTime = 0.0f;
		txtPrms.fadeoutTime = 0.1f;
		txtPrms.holdTime = 0.5f;
		txtPrms.channel = 3;
		
		string msg = string(actor.pev.netname) + "\nHP: " + Math.Ceil(actor.pev.health)
						+ "    AP: " + Math.Ceil(actor.pev.armorvalue);
		
		if (actorWep !is null) {
			int primaryAmmo = actorWep.m_iPrimaryAmmoType != -1 ? actor.m_rgAmmo( actorWep.m_iPrimaryAmmoType ) : 0;
			int secondaryAmmo = actorWep.m_iSecondaryAmmoType != -1 ? actor.m_rgAmmo( actorWep.m_iSecondaryAmmoType ) : 0;
			
			if (actorWep.m_iPrimaryAmmoType != -1) {
				msg += "    Ammo: ";
				
				if (actorWep.m_iClip != -1) {
					msg += "" + actorWep.m_iClip + " | ";
				}
				if (actorWep.m_iSecondaryAmmoType != -1) {
					int count = actor.m_rgAmmo( actorWep.m_iSecondaryAmmoType ) + (actorWep.m_iClip2 != -1 ? actorWep.m_iClip2 : 0);
					msg += "" + count + " | ";
				}
				if (actorWep.m_iPrimaryAmmoType != -1) {
					msg += "" + actor.m_rgAmmo( actorWep.m_iPrimaryAmmoType );
				}
			}
		}
		
		HudMessageUnreliable(viewer, txtPrms, msg);
		g_EngineFuncs.SetView(viewer.edict(), infoent.edict());
	}
	
	g_Scheduler.SetTimeout("view_loop", 0, @viewdat);
}

uint16 FixedUnsigned16( float value, float scale ) {
   float scaled = value * scale;
   int output = int( scaled );
   
   if ( output < 0 )
      output = 0;
   if ( output > 0xFFFF )
      output = 0xFFFF;

   return uint16( output );
}

int16 FixedSigned16( float value, float scale ) {
   float scaled = value * scale;
   int output = int( scaled );

   if ( output > 32767 )
      output = 32767;
   if ( output < -32768 )
      output = -32768;

   return int16( output );
}

void HudCustomSpriteMsg(edict_t@ targetPlr, HUDSpriteParams params, NetworkMessageDest msg_dest=MSG_ONE_UNRELIABLE) {
	NetworkMessage m(msg_dest, NetworkMessages::CustSpr, targetPlr);

	m.WriteByte(params.channel);
	m.WriteLong(params.flags);
	m.WriteString(params.spritename);
	m.WriteByte(params.left);
	m.WriteByte(params.top);
	m.WriteShort(params.width);
	m.WriteShort(params.height);
	m.WriteFloat(params.x);
	m.WriteFloat(params.y);
	m.WriteByte(params.color1.r);
	m.WriteByte(params.color1.g);
	m.WriteByte(params.color1.b);
	m.WriteByte(params.color1.a);
	m.WriteByte(params.color2.r);
	m.WriteByte(params.color2.g);
	m.WriteByte(params.color2.b);
	m.WriteByte(params.color2.a);
	m.WriteByte(params.frame);
	m.WriteByte(params.numframes);
	m.WriteFloat(params.framerate);
	m.WriteFloat(params.fadeinTime);
	m.WriteFloat(params.fadeoutTime);
	m.WriteFloat(params.holdTime);
	m.WriteFloat(params.fxTime);
	m.WriteByte(params.effect);

	m.End();
}

// find a player by name or partial name or steam id
CBasePlayer@ getPlayerByName(CBasePlayer@ caller, string name)
{
	name = name.ToLowercase();
	int partialMatches = 0;
	CBasePlayer@ partialMatch;
	
	for (int i = 1; i <= g_Engine.maxClients; i++) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected() || plr.entindex() == caller.entindex()) {
			continue;
		}
		
		const string steamId = g_EngineFuncs.GetPlayerAuthId(plr.edict()).ToLowercase();
		
		string plrName = string(plr.pev.netname).ToLowercase();
		if (plrName == name || steamId == name)
			return plr;
		else if (plrName.Find(name) != uint(-1))
		{
			@partialMatch = plr;
			partialMatches++;
		}
	}
	
	if (partialMatches == 1) {
		return partialMatch;
	} else if (partialMatches > 1) {
		g_PlayerFuncs.ClientPrint(caller, HUD_PRINTNOTIFY, 'There are ' + partialMatches + ' players that have "' + name + '" in their name. Be more specific.\n');
	} else {
		g_PlayerFuncs.ClientPrint(caller, HUD_PRINTNOTIFY, 'There is no player named "' + name + '".\n');
	}
	
	return null;
}

void viewMenuCallback(CTextMenu@ menu, CBasePlayer@ plr, int itemNumber, const CTextMenuItem@ item) {
	if (item is null or plr is null or !plr.IsConnected())
		return;
	string option = "";
	item.m_pUserData.retrieve(option);
	const array<string> values = option.Split("+");

	int currentIdx = g_viewents[plr.entindex()].targetidx;

	CBasePlayer@ target = getPlayerByName(plr, values[0]);
	if (target !is null) {
		CBasePlayer@ currentTarget = g_PlayerFuncs.FindPlayerByIndex(currentIdx);
		
		if (currentTarget !is null and currentTarget.entindex() == target.entindex()) {
			g_viewents[plr.entindex()].Remove();
		} else {
			viewPlayer(plr, target);
		}
	}	
	
	g_Scheduler.SetTimeout("openViewMenu", 0.0f, EHandle(plr), atoi(values[1])); // wait a frame or else game crashes
}

void openViewMenu(EHandle h_plr, int pageNum) {
	CBasePlayer@ viewer = cast<CBasePlayer@>(h_plr.GetEntity());
	if (viewer is null) {
		return;
	}
	
	int eidx = viewer.entindex();

	@g_menus[eidx] = CTextMenu(@viewMenuCallback);
	g_menus[eidx].SetTitle("\\yView menu");
	
	array<CBasePlayer@> possibleTargets;
	for ( int i = 1; i <= g_Engine.maxClients; i++ ) {
		CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(i);
		
		if (plr is null or !plr.IsConnected() || plr.Classify() != viewer.Classify() || plr.entindex() == viewer.entindex()) {
			continue;
		}
		possibleTargets.insertLast(plr);
	}
	
	const bool moreThanOnePage = possibleTargets.size() > 9;
	
	if (possibleTargets.size() == 0) {
		g_PlayerFuncs.ClientPrint(viewer, HUD_PRINTTALK, 'No players are viewable\n');
		return;
	}

	CBasePlayer@ actor = g_PlayerFuncs.FindPlayerByIndex(g_viewents[viewer.entindex()].targetidx);
	
	for (uint i = 0; i < possibleTargets.size(); i++) {
		CBasePlayer@ plr = possibleTargets[i];
		
		int itemPage = moreThanOnePage ? (i / 7) : 0;
		bool isSelected = actor !is null and actor.entindex() == plr.entindex();
		string color = isSelected ? "\\r" : "\\w";
		string steamid = g_EngineFuncs.GetPlayerAuthId(plr.edict());
		g_menus[eidx].AddItem(color + plr.pev.netname + "\\y", any(steamid + "+" + itemPage));
	}

	g_menus[eidx].Register();
	g_menus[eidx].Open(0, pageNum, viewer);
}

void viewPlayer(CBasePlayer@ viewer, CBasePlayer@ actor, bool updateOnly=false) {
	g_viewents[viewer.entindex()].Remove();
			
	CBaseEntity@ viewent = g_EntityFuncs.CreateEntity("monster_ghost", {
		{'origin', actor.pev.origin.ToString()},
		{'angles', actor.pev.v_angle.ToString()},
		{'model', "models/v_9mmhandgun.mdl"}
	}, true);
	viewent.pev.movetype = MOVETYPE_NOCLIP;
	viewent.pev.solid = SOLID_NOT;
	viewent.pev.renderamt = 0;
	viewent.pev.rendermode = 1;
	
	CBaseMonster@ wepent = cast<CBaseMonster@>(g_EntityFuncs.CreateEntity("monster_ghost", {
		{'targetname', "as_view_wep_" + viewer.entindex()},
		{'origin', actor.pev.origin.ToString()},
		{'angles', actor.pev.v_angle.ToString()},
		{'rendermode', "1"},
		{'model', "models/v_9mmhandgun.mdl"}
	}, true));
	wepent.pev.movetype = MOVETYPE_NOCLIP;
	wepent.pev.solid = SOLID_NOT;
	
	CBaseEntity@ hideTargetModel = g_EntityFuncs.CreateEntity("env_render_individual", {
		{'target', "as_view_plr_" + viewer.entindex()},
		{'origin', viewer.pev.origin.ToString()},
		{'targetname', "as_view_render_" + viewer.entindex()},
		{'spawnflags', "" + (1 | 8 | 64)}, // no renderfx + no rendercolor + affect activator
		{'rendermode', "1"},
		{'renderamt', "0"}
	}, true);
	
	CBaseEntity@ showTargetWep = g_EntityFuncs.CreateEntity("env_render_individual", {
		{'target', "as_view_wep_" + viewer.entindex()},
		{'origin', viewer.pev.origin.ToString()},
		{'targetname', "as_view_render_" + viewer.entindex()},
		{'spawnflags', "" + (1 | 2 | 8 | 64)}, // no renderfx + no renderamt + no rendercolor + affect activator
		{'rendermode', "0"},
		{'renderamt', "0"}
	}, true);
	
	CBaseEntity@ icon = g_EntityFuncs.CreateEntity("env_sprite", {
		{'origin', viewer.pev.origin.ToString()},
		{'model', eye_spr},
		{'spawnflags', "1"},
		{'rendermode', "4"},
		{'renderamt', "128"},
		{'scale', "0.165"}
	}, true);
	icon.pev.movetype = MOVETYPE_FOLLOW;
	@icon.pev.aiment = @viewer.edict();
	
	g_viewents[viewer.entindex()] = ViewDat(EHandle(viewent), EHandle(viewer), actor.entindex(),
	EHandle(wepent), EHandle(hideTargetModel), EHandle(showTargetWep), EHandle(icon));
	
	// hide the target's player model
	string oldName = actor.pev.targetname;
	actor.pev.targetname = hideTargetModel.pev.target;
	hideTargetModel.Use(viewer, viewer, USE_ON);
	actor.pev.targetname = oldName;
	
	// show a fake weapon for the target
	showTargetWep.Use(viewer, viewer, USE_ON);
	
	// prevent weapon zoom messing up fov on target
	CBasePlayerWeapon@ wep = cast<CBasePlayerWeapon@>(viewer.m_hActiveItem.GetEntity());
	if (wep !is null) {
		string cname = wep.pev.classname;
		if (viewer.m_iFOV != 0 && (cname == "weapon_9mmAR" || cname == "weapon_crossbow")) {
			wep.SecondaryAttack();
		}
	}
	
	g_playerdat[actor.entindex()].specCount += 1;
	g_viewents[viewer.entindex()].lastHudUpdate = 0;
	g_viewents[viewer.entindex()].hideAttachments();
	g_playerdat[viewer.entindex()].lastViewTarget = g_EngineFuncs.GetPlayerAuthId(actor.edict());
	clientCommand(viewer, "stopsound");
	
	if (g_playerdat[actor.entindex()].lastNotify[viewer.entindex()] + 3.0f < g_Engine.time) {
		g_playerdat[actor.entindex()].lastNotify[viewer.entindex()] = g_Engine.time;
		g_PlayerFuncs.ClientPrint(actor, HUD_PRINTNOTIFY, "[View] " + string(viewer.pev.netname) + ' viewed your screen.\n');
	}
	
	if (!updateOnly)
		view_loop(@g_viewents[viewer.entindex()]);
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args, bool inConsole) {
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	
	if (args.ArgC() >= 1)
	{
		if (args[0] == ".observer" || args[0] == ".observe" || args[0] == ".spectate") {
			float cooldown_time = Math.max(g_EngineFuncs.CVarGetFloat("mp_respawndelay"), 1.0f);
			float delta = g_Engine.time - g_playerdat[plr.entindex()].lastObserverCommand;
			if (delta < cooldown_time) {
				g_PlayerFuncs.SayText(plr, "Wait " + int((cooldown_time - delta) + 0.99f) + " seconds before toggling observer mode again.\n");
				return true;
			}
			
			g_playerdat[plr.entindex()].lastObserverCommand = g_Engine.time;
			
			g_playerdat[plr.entindex()].wantsSpectate = !g_playerdat[plr.entindex()].wantsSpectate;
			
			if (plr.GetObserver() !is null && plr.GetObserver().IsObserver()) {
				if (g_SurvivalMode.IsActive()) {
					g_PlayerFuncs.SayText(plr, "Can't respawn while survival mode is on.\n");
				} else {
					if (plr.m_flRespawnDelayTime != 0) {
						g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "" + plr.pev.netname + " stopped observing.\n");
					}
					g_PlayerFuncs.RespawnPlayer(plr, true, true);
				}
			} else {
				bool wasAlive = plr.IsAlive();
			
				if (wasAlive) {
					plr.Killed(plr.pev, GIB_ALWAYS);
				}
				
				plr.GetObserver().StartObserver(plr.pev.origin, plr.pev.v_angle, true);
				
				if (!wasAlive && plr.GetObserver().HasCorpse()) {
					plr.GetObserver().RemoveDeadBody();
				}
				
				if (!g_SurvivalMode.IsActive()) {
					g_Scheduler.SetTimeout("delay_respawn", 0.1f, EHandle(plr));
					g_PlayerFuncs.ClientPrintAll(HUD_PRINTNOTIFY, "" + plr.pev.netname + " is observing.\n");
				}
			}

			return true;
		}
		if (args[0] == ".views") {		
			if (g_playerdat[plr.entindex()].lastViewCommand + 0.2f > g_Engine.time) {
				return true;
			}
			g_playerdat[plr.entindex()].lastViewCommand = g_Engine.time;
			
			array<array<string>> actors;
			actors.resize(33);
			
			for (int i = 1; i <= g_Engine.maxClients; i++) {
				CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
				
				if (p is null or !p.IsConnected()) {
					continue;
				}
				
				if (g_viewents[i].targetidx != -1) {
					actors[g_viewents[i].targetidx].insertLast(p.pev.netname);
				}
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "\nPlayers who are being viewed\n----------------------------\n");
			
			bool anyWatched = false;
			
			for (uint i = 1; i < actors.size(); i++) {
				CBasePlayer@ p = g_PlayerFuncs.FindPlayerByIndex(i);
				
				if (p is null or !p.IsConnected()) {
					continue;
				}
				
				if (actors[i].size() == 0) {
					continue;
				}
				
				anyWatched = true;
				
				string watchers = "";
				for (uint k = 0; k < actors[i].size(); k++) {
					watchers += "    " + actors[i][k] + "\n";
				}
				
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, string(p.pev.netname) + ':\n' + watchers + "\n");
			}
			
			if (!anyWatched) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "(nobody)\n");
			}
			
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, "----------------------------\n\n");
			
			return true;
		}
		if (args[0] == ".viewhelp") {
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, 'Usage:\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, '    ".view" to open the view menu.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, '    ".view [name/steamid]" to see another player\'s perspective.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, '    ".viewlast" to toggle between your view and the last selected view.\n');
			g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, '    ".views" to see who is viewing (in console).\n');
			return true;
		}
		if (args[0] == ".view" || args[0] == ".viewlast") {
			if (g_playerdat[plr.entindex()].lastViewCommand + 0.2f > g_Engine.time) {
				return true;
			}
			g_playerdat[plr.entindex()].lastViewCommand = g_Engine.time;
		
			bool isLastToggle = args[0] == ".viewlast";
			bool isViewing = g_viewents[plr.entindex()].isViewing();
			
			if (!isLastToggle and args.ArgC() == 1) {
				openViewMenu(EHandle(plr), 0);
				return true;
			}
			
			if (isLastToggle && isViewing) {
				g_viewents[plr.entindex()].Remove();
				return true;
			}
			
			string searchString = isLastToggle ? g_playerdat[plr.entindex()].lastViewTarget : args[1];			
			CBasePlayer@ target = getPlayerByName(plr, searchString);
			
			if (target !is null) {
				if (target.Classify() != plr.Classify()) {
					g_PlayerFuncs.ClientPrint(plr, HUD_PRINTTALK, 'Can\'t view enemy screens.\n');
					return true;
				}
				
				viewPlayer(plr, target, isViewing);
			}
				
			return true;
		}
	}
	
	return false;
}

void clientCommand(CBaseEntity@ plr, string cmd) {
	NetworkMessage m(MSG_ONE, NetworkMessages::NetworkMessageType(9), plr.edict());
		m.WriteString(";" + cmd + ";");
	m.End();
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	if (args.ArgC() > 0 && doCommand(plr, args, false))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	return HOOK_CONTINUE;
}

CClientCommand _g("observer", "Spectate commands", @consoleCmd );
CClientCommand _g2("observe", "Spectate commands", @consoleCmd );
CClientCommand _g3("spectate", "Spectate commands", @consoleCmd );
CClientCommand _g4("view", "Spectate commands", @consoleCmd );
CClientCommand _g5("viewlast", "Spectate commands", @consoleCmd );
CClientCommand _g6("views", "Spectate commands", @consoleCmd );
CClientCommand _g7("viewhelp", "Spectate commands", @consoleCmd );

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}