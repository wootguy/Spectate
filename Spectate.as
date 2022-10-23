void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

void PluginInit()
{	
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "https://github.com/wootguy/" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	
	lastCommandTime.resize(0);
	lastCommandTime.resize(33);
}

void MapInit() {
	lastCommandTime.resize(0);
	lastCommandTime.resize(33);
}

void delay_respawn(EHandle h_plr) {
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	if (plr is null) {
		return;
	}
	
	// the player respawn hooks don't work, so this has to be done to prevent respawning.
	plr.m_flRespawnDelayTime = 100000 - g_EngineFuncs.CVarGetFloat("mp_respawndelay");
}

array<float> lastCommandTime;

bool doCommand(CBasePlayer@ plr, const CCommand@ args, bool inConsole) {
	bool isAdmin = g_PlayerFuncs.AdminLevel(plr) >= ADMIN_YES;
	
	if (args.ArgC() >= 1)
	{
		if (args[0] == ".observer" || args[0] == ".observe" || args[0] == ".spectate") {
			float cooldown_time = Math.max(g_EngineFuncs.CVarGetFloat("mp_respawndelay"), 1.0f);
			float delta = g_Engine.time - lastCommandTime[plr.entindex()];
			if (delta < cooldown_time) {
				g_PlayerFuncs.SayText(plr, "Wait " + int((cooldown_time - delta) + 0.99f) + " seconds before toggling observer mode again.\n");
				return true;
			}
			
			lastCommandTime[plr.entindex()] = g_Engine.time;
			
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
	}
	
	return false;
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

void consoleCmd( const CCommand@ args ) {
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args, true);
}