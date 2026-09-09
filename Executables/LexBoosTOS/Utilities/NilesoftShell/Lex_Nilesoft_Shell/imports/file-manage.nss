menu(where=sel.count>0 type='file|dir|drive|namespace|back' mode="multiple" title=loc.file_manage image=\uE253)
{
	menu(separator="after" title=title.copy_path image=icon.copy_path)
	{
		item(where=sel.count > 1 title='Copy (@sel.count) items selected' cmd=command.copy(sel(false, "\n")))
		item(mode="single" title=@sel.path tip=sel.path cmd=command.copy(sel.path))
		item(mode="single" type='file' separator="before" find='.lnk' title='open file location')
		separator
		item(mode="single" where=@sel.parent.len>3 title=sel.parent cmd=@command.copy(sel.parent))
		separator
		item(mode="single" type='file|dir|back.dir' title=sel.file.name cmd=command.copy(sel.file.name))
		item(mode="single" type='file' where=sel.file.len != sel.file.title.len title=@sel.file.title cmd=command.copy(sel.file.title))
		item(mode="single" type='file' where=sel.file.ext.len>0 title=sel.file.ext cmd=command.copy(sel.file.ext))
	}

	item(mode="single" type="file" title=loc.change_extension image=\uE0B5 cmd=if(input(loc.change_extension, "Type extension"),
		io.rename(sel.path, path.join(sel.dir, sel.file.title + "." + input.result))))

	menu(separator="after" image=\uE290 title=title.select)
	{
		item(title=loc.all image=icon.select_all cmd=command.select_all)
		item(title=loc.invert image=icon.invert_selection cmd=command.invert_selection)
		item(title=loc.none image=icon.select_none cmd=command.select_none)
	}

	item(type='file|dir|back.dir|drive' title=loc.take_ownership image=[\uE194,#f00] admin
		cmd args='/K takeown /f "@sel.path" @if(sel.type==1,null,"/r /d O") && icacls "@sel.path" /grant *S-1-5-32-544:F @if(sel.type==1,"/c /l","/t /c /l /q")')
	separator
	menu(title=loc.show_hide image=icon.show_hidden_files)
	{
		item(title=loc.system_files image=inherit cmd='@command.togglehidden')
		item(title=loc.file_name_extensions image=icon.show_file_extensions cmd='@command.toggleext')
	}

	menu(mode="single" type='dir|dir.back' sep="top" title=loc.add_to_path image=\uE218)
	{
		item(title=loc.path_user image=\uE108 cmd args='/c setx PATH "%PATH%;@sel.path"' window=hidden)
		item(title=loc.path_system image=\uE192 admin cmd args='/c setx /M PATH "%PATH%;@sel.path"' window=hidden)
	}

	menu(mode="single" type='file' find='.dll|.ocx' separator="before" title=loc.register_erver image=\uea86)
	{
		item(title=loc.register admin cmd='regsvr32.exe' args='@sel.path.quote' invoke="multiple")
		item(title=loc.unregister admin cmd='regsvr32.exe' args='/u @sel.path.quote' invoke="multiple")
	}

	item(where=!wnd.is_desktop title=title.folder_options image=icon.folder_options cmd=command.folder_options)
}
