menu(where=sel.count>0 type='file|dir|drive|namespace|back' mode="multiple" title=loc.file_manage image=\uE253)
{
	menu(separator="after" title=title.copy_path image=icon.copy_path)
	{
		item(where=sel.count > 1 title=loc.copy_multiple_paths cmd=command.copy(sel(false, "\n")))
		item(mode="single" title=@sel.path tip=sel.path cmd=command.copy(sel.path))
		item(mode="single" type='file' separator="before" where=length(sel.lnk)>0 title=sel.lnk cmd=command.copy(sel.lnk))
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

	item(where=!wnd.is_desktop title=title.folder_options image=icon.folder_options cmd=command.folder_options)
}