menu(type='*' where=(sel.count or wnd.is_taskbar or wnd.is_edit) title=title.terminal sep=sep.top image=icon.run_with_powershell)
{
	$tip_run_admin=["\xE1A7 Press [SHIFT key] or [RIGHT-CLICK] to run " + this.title + " as administrator", tip.warning, 1.0]
	$has_admin=key.shift() or key.rbutton()
	
	item(title=title.command_prompt tip=tip_run_admin admin=has_admin image cmd-prompt=`/K TITLE Command Prompt &ver& PUSHD "@sel.dir"`)
	item(title=title.windows_powershell admin=has_admin tip=tip_run_admin image cmd-ps=`-noexit -command Set-Location -Path '@sel.dir'`)
	item(where=package.exists("WindowsTerminal")
			title=title.Windows_Terminal
			tip=tip_run_admin
			admin=has_admin
			image='@package.path("WindowsTerminal")\WindowsTerminal.exe'
			cmd="wt.exe"
			arg=`-d "@sel.path\."`)

	sep()
	item(title='Invite de commandes (Admin)' admin=true image cmd-prompt=`/K TITLE Command Prompt (Admin) &ver& PUSHD "@sel.dir"`)
	item(title='Windows PowerShell (Admin)' admin=true image cmd-ps=`-noexit -command Set-Location -Path '@sel.dir'`)
	item(where=package.exists("WindowsTerminal")
			title='Windows Terminal (Admin)'
			admin=true
			image='@package.path("WindowsTerminal")\WindowsTerminal.exe'
			cmd="wt.exe"
			arg=`-d "@sel.path\."`)
}

// PowerShell .ps1 script menu
menu(mode="single" type='file' find='.ps1' title='Script PowerShell' image=icon.run_with_powershell)
{
	item(title='Exécuter avec PowerShell' image=icon.run_with_powershell cmd='powershell.exe' args='-ExecutionPolicy Bypass -File @sel.path.quote')
	item(title='Exécuter avec PowerShell (Admin)' image=icon.run_with_powershell admin=true cmd='powershell.exe' args='-ExecutionPolicy Bypass -File @sel.path.quote')
}

// Batch .bat/.cmd script menu
menu(mode="single" type='file' find='.bat|.cmd' title='Script Batch' image=icon.run_with_powershell)
{
	item(title='Exécuter' image=icon.run_with_powershell cmd='cmd.exe' args='/K @sel.path.quote')
	item(title='Exécuter (Admin)' image=icon.run_with_powershell admin=true cmd='cmd.exe' args='/K @sel.path.quote')
}