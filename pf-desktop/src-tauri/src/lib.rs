use tauri::Manager;
use tauri::Emitter;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri_plugin_autostart::MacosLauncher;
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};

#[cfg(target_os = "macos")]
mod macos;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .plugin(tauri_plugin_dialog::init())
    .plugin(tauri_plugin_notification::init())
    .plugin(tauri_plugin_autostart::init(MacosLauncher::LaunchAgent, None))
    .menu(|app| build_menu(app))
    .setup(|app| {
      let _ = build_tray(app.handle());
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }
      #[cfg(target_os = "macos")]
      {
        let _ = macos::touchbar::install(app.handle());
      }
      Ok(())
    })
    .on_menu_event(|app, event| {
      match event.id().0.as_str() {
        "file.export_backup" => {
          let _ = app.emit("menu:export_backup", ());
        }
        "file.import_backup_folder" => {
          let _ = app.emit("menu:import_backup_folder", ());
        }
        "file.import_backup_json" => {
          let _ = app.emit("menu:import_backup_json", ());
        }
        "app.open_settings" => {
          let _ = app.emit("menu:open_settings", ());
        }
        _ => {}
      }
    })
    .invoke_handler(tauri::generate_handler![
      app_data_dir,
      read_data_file,
      write_data_file,
      preserve_corrupt_file,
      attachments_root_dir,
      save_bill_attachment,
      delete_bill_attachment,
      delete_all_attachments,
      export_backup,
      export_calendar_ics,
      read_backup_source,
      restore_attachments_from
    ])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}

fn build_menu(app: &tauri::AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
  let export = MenuItem::with_id(app, "file.export_backup", "Export Backup…", true, Some("CmdOrCtrl+E"))?;
  let import_folder = MenuItem::with_id(app, "file.import_backup_folder", "Import Backup Folder…", true, Some("CmdOrCtrl+I"))?;
  let import_json = MenuItem::with_id(app, "file.import_backup_json", "Import Backup JSON…", true, None::<&str>)?;
  let settings = MenuItem::with_id(app, "app.open_settings", "Settings…", true, Some("CmdOrCtrl+,"))?;

  let file = Submenu::new(app, "File", true)?;
  file.append(&export)?;
  file.append(&import_folder)?;
  file.append(&import_json)?;
  file.append(&PredefinedMenuItem::separator(app)?)?;
  file.append(&PredefinedMenuItem::quit(app, Some("Quit"))?)?;

  let edit = Submenu::new(app, "Edit", true)?;
  edit.append(&PredefinedMenuItem::undo(app, None)?)?;
  edit.append(&PredefinedMenuItem::redo(app, None)?)?;
  edit.append(&PredefinedMenuItem::separator(app)?)?;
  edit.append(&PredefinedMenuItem::cut(app, None)?)?;
  edit.append(&PredefinedMenuItem::copy(app, None)?)?;
  edit.append(&PredefinedMenuItem::paste(app, None)?)?;
  edit.append(&PredefinedMenuItem::select_all(app, None)?)?;

  let app_menu = Submenu::new(app, "App", true)?;
  app_menu.append(&settings)?;

  let menu = Menu::new(app)?;
  menu.append(&app_menu)?;
  menu.append(&file)?;
  menu.append(&edit)?;
  Ok(menu)
}

fn build_tray(app: &tauri::AppHandle) -> tauri::Result<()> {
  let show = MenuItem::with_id(app, "tray.show", "Show", true, None::<&str>)?;
  let hide = MenuItem::with_id(app, "tray.hide", "Hide", true, None::<&str>)?;
  let export = MenuItem::with_id(app, "tray.export_backup", "Export Backup…", true, None::<&str>)?;
  let settings = MenuItem::with_id(app, "tray.open_settings", "Settings…", true, None::<&str>)?;
  let quit = MenuItem::with_id(app, "tray.quit", "Quit", true, None::<&str>)?;

  let menu = Menu::new(app)?;
  menu.append(&show)?;
  menu.append(&hide)?;
  menu.append(&PredefinedMenuItem::separator(app)?)?;
  menu.append(&export)?;
  menu.append(&settings)?;
  menu.append(&PredefinedMenuItem::separator(app)?)?;
  menu.append(&quit)?;

  TrayIconBuilder::new()
    .menu(&menu)
    .on_menu_event(move |app, event| {
      match event.id().0.as_str() {
        "tray.show" => {
          if let Some(w) = app.get_webview_window("main") {
            let _ = w.show();
            let _ = w.set_focus();
          }
        }
        "tray.hide" => {
          if let Some(w) = app.get_webview_window("main") {
            let _ = w.hide();
          }
        }
        "tray.export_backup" => {
          let _ = app.emit("menu:export_backup", ());
        }
        "tray.open_settings" => {
          let _ = app.emit("menu:open_settings", ());
        }
        "tray.quit" => {
          app.exit(0);
        }
        _ => {}
      }
    })
    .on_tray_icon_event(move |tray, event| {
      if let TrayIconEvent::Click { button, button_state, .. } = event {
        if button == MouseButton::Left && button_state == MouseButtonState::Up {
          let app = tray.app_handle();
          if let Some(w) = app.get_webview_window("main") {
            let _ = w.show();
            let _ = w.set_focus();
          }
        }
      }
    })
    .build(app)?;

  Ok(())
}

fn allowed_data_file(name: &str) -> Option<&'static str> {
  match name {
    "bills.json" => Some("bills.json"),
    "incomes.json" => Some("incomes.json"),
    "accounts.json" => Some("accounts.json"),
    "transactions.json" => Some("transactions.json"),
    "goals.json" => Some("goals.json"),
    "debts.json" => Some("debts.json"),
    "settings.json" => Some("settings.json"),
    "command_memory.json" => Some("command_memory.json"),
    _ => None,
  }
}

fn data_root(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
  let base = app
    .path()
    .app_data_dir()
    .map_err(|e| e.to_string())?;
  Ok(base.join("Kivana"))
}

fn attachments_root(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
  let root = data_root(app)?.join("Attachments");
  std::fs::create_dir_all(&root).map_err(|e| e.to_string())?;
  Ok(root)
}

#[tauri::command]
fn app_data_dir(app: tauri::AppHandle) -> Result<String, String> {
  let p = data_root(&app)?;
  Ok(p.to_string_lossy().to_string())
}

#[tauri::command]
fn attachments_root_dir(app: tauri::AppHandle) -> Result<String, String> {
  let p = attachments_root(&app)?;
  Ok(p.to_string_lossy().to_string())
}

#[tauri::command]
fn read_data_file(app: tauri::AppHandle, name: String) -> Result<Option<String>, String> {
  let file = allowed_data_file(&name).ok_or_else(|| "unsupported file".to_string())?;
  let root = data_root(&app)?;
  let path = root.join(file);
  if !path.exists() {
    return Ok(None);
  }
  let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
  let text = String::from_utf8(bytes).map_err(|e| e.to_string())?;
  Ok(Some(text))
}

#[tauri::command]
fn write_data_file(app: tauri::AppHandle, name: String, content: String) -> Result<(), String> {
  let file = allowed_data_file(&name).ok_or_else(|| "unsupported file".to_string())?;
  let root = data_root(&app)?;
  std::fs::create_dir_all(&root).map_err(|e| e.to_string())?;
  let path = root.join(file);
  let tmp_name = format!(
    "{}.tmp-{}-{}",
    file,
    std::process::id(),
    std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .map_err(|e| e.to_string())?
      .as_millis()
  );
  let tmp_path = root.join(tmp_name);
  std::fs::write(&tmp_path, content.as_bytes()).map_err(|e| e.to_string())?;
  if path.exists() {
    let _ = std::fs::remove_file(&path);
  }
  std::fs::rename(&tmp_path, &path).map_err(|e| e.to_string())?;
  Ok(())
}

#[tauri::command]
fn preserve_corrupt_file(app: tauri::AppHandle, name: String) -> Result<(), String> {
  let file = allowed_data_file(&name).ok_or_else(|| "unsupported file".to_string())?;
  let root = data_root(&app)?;
  let path = root.join(file);
  if !path.exists() {
    return Ok(());
  }
  std::fs::create_dir_all(&root).map_err(|e| e.to_string())?;
  let stamp = std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .map_err(|e| e.to_string())?
    .as_secs();
  let backup = format!("{}.corrupt-{}.json", file.trim_end_matches(".json"), stamp);
  let backup_path = root.join(backup);
  let _ = std::fs::copy(&path, &backup_path);
  Ok(())
}

fn is_absolute_path(path: &str) -> bool {
  std::path::Path::new(path).is_absolute()
}

fn copy_dir_recursive(source: &std::path::Path, dest: &std::path::Path) -> Result<(), String> {
  if !source.exists() {
    return Ok(());
  }
  std::fs::create_dir_all(dest).map_err(|e| e.to_string())?;
  for entry in std::fs::read_dir(source).map_err(|e| e.to_string())? {
    let entry = entry.map_err(|e| e.to_string())?;
    let src = entry.path();
    let file_name = entry.file_name();
    let dst = dest.join(file_name);
    let file_type = entry.file_type().map_err(|e| e.to_string())?;
    if file_type.is_dir() {
      copy_dir_recursive(&src, &dst)?;
    } else if file_type.is_file() {
      if let Some(parent) = dst.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
      }
      if dst.exists() {
        let _ = std::fs::remove_file(&dst);
      }
      std::fs::copy(&src, &dst).map_err(|e| e.to_string())?;
    }
  }
  Ok(())
}

#[derive(serde::Serialize)]
struct SavedAttachment {
  stored_relative_path: String,
  display_name: String,
}

#[tauri::command]
fn save_bill_attachment(
  app: tauri::AppHandle,
  bill_id: String,
  attachment_id: String,
  source_path: String,
  display_name: Option<String>,
) -> Result<SavedAttachment, String> {
  if bill_id.trim().is_empty() {
    return Err("bill_id required".to_string());
  }
  if attachment_id.trim().is_empty() {
    return Err("attachment_id required".to_string());
  }
  if !is_absolute_path(&source_path) {
    return Err("source_path must be absolute".to_string());
  }

  let src = std::path::PathBuf::from(&source_path);
  if !src.exists() {
    return Err("source file does not exist".to_string());
  }
  let ext = src
    .extension()
    .and_then(|s| s.to_str())
    .filter(|s| !s.trim().is_empty())
    .unwrap_or("dat");
  let stored_file_name = format!("{}.{}", attachment_id, ext);

  let root = attachments_root(&app)?;
  let bill_dir = root.join(&bill_id);
  std::fs::create_dir_all(&bill_dir).map_err(|e| e.to_string())?;
  let dest = bill_dir.join(&stored_file_name);

  if dest.exists() {
    let _ = std::fs::remove_file(&dest);
  }
  std::fs::copy(&src, &dest).map_err(|e| e.to_string())?;

  let relative = format!("{}/{}", bill_id, stored_file_name);
  let fallback_name = src
    .file_name()
    .and_then(|s| s.to_str())
    .filter(|s| !s.trim().is_empty())
    .unwrap_or(&stored_file_name)
    .to_string();
  let dn = display_name
    .unwrap_or(fallback_name)
    .trim()
    .to_string();

  Ok(SavedAttachment {
    stored_relative_path: relative,
    display_name: dn,
  })
}

#[tauri::command]
fn delete_bill_attachment(app: tauri::AppHandle, stored_relative_path: String) -> Result<(), String> {
  if stored_relative_path.contains("..") {
    return Err("invalid stored_relative_path".to_string());
  }
  let root = attachments_root(&app)?;
  let path = root.join(stored_relative_path);
  if path.exists() {
    std::fs::remove_file(&path).map_err(|e| e.to_string())?;
  }
  Ok(())
}

#[tauri::command]
fn delete_all_attachments(app: tauri::AppHandle) -> Result<(), String> {
  let root = attachments_root(&app)?;
  if root.exists() {
    std::fs::remove_dir_all(&root).map_err(|e| e.to_string())?;
  }
  Ok(())
}

#[tauri::command]
fn export_backup(
  app: tauri::AppHandle,
  bundle_dir_path: String,
  backup_json: String,
  attachment_paths: Vec<String>,
) -> Result<(), String> {
  if !is_absolute_path(&bundle_dir_path) {
    return Err("bundle_dir_path must be absolute".to_string());
  }
  if !bundle_dir_path.to_lowercase().ends_with(".pfbackup") {
    return Err("bundle_dir_path must end with .pfbackup".to_string());
  }
  let bundle_dir = std::path::PathBuf::from(&bundle_dir_path);
  if bundle_dir.exists() {
    std::fs::remove_dir_all(&bundle_dir).map_err(|e| e.to_string())?;
  }
  std::fs::create_dir_all(&bundle_dir).map_err(|e| e.to_string())?;

  let json_path = bundle_dir.join("backup.json");
  std::fs::write(&json_path, backup_json.as_bytes()).map_err(|e| e.to_string())?;

  let bundle_attachments_root = bundle_dir.join("Attachments");
  std::fs::create_dir_all(&bundle_attachments_root).map_err(|e| e.to_string())?;

  let app_attachments_root = attachments_root(&app)?;
  let mut unique: std::collections::HashSet<String> = std::collections::HashSet::new();
  for p in attachment_paths {
    if p.contains("..") {
      continue;
    }
    unique.insert(p);
  }
  for rel in unique {
    let src = app_attachments_root.join(&rel);
    if !src.exists() {
      continue;
    }
    let dest = bundle_attachments_root.join(&rel);
    if let Some(parent) = dest.parent() {
      std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    if dest.exists() {
      let _ = std::fs::remove_file(&dest);
    }
    std::fs::copy(&src, &dest).map_err(|e| e.to_string())?;
  }

  Ok(())
}

#[tauri::command]
fn export_calendar_ics(destination_path: String, ics_content: String) -> Result<(), String> {
  if !is_absolute_path(&destination_path) {
    return Err("destination_path must be absolute".to_string());
  }
  if !destination_path.to_lowercase().ends_with(".ics") {
    return Err("destination_path must end with .ics".to_string());
  }
  let p = std::path::PathBuf::from(destination_path);
  std::fs::write(&p, ics_content.as_bytes()).map_err(|e| e.to_string())?;
  Ok(())
}

#[derive(serde::Serialize)]
struct BackupSource {
  json: String,
  attachments_source_dir: Option<String>,
}

#[tauri::command]
fn read_backup_source(path: String) -> Result<BackupSource, String> {
  if !is_absolute_path(&path) {
    return Err("path must be absolute".to_string());
  }
  let p = std::path::PathBuf::from(&path);
  let lower = path.to_lowercase();
  if lower.ends_with(".pfbackup") {
    let json_path = p.join("backup.json");
    let bytes = std::fs::read(&json_path).map_err(|e| e.to_string())?;
    let text = String::from_utf8(bytes).map_err(|e| e.to_string())?;
    let attachments = p.join("Attachments");
    let dir = if attachments.exists() {
      Some(attachments.to_string_lossy().to_string())
    } else {
      None
    };
    return Ok(BackupSource {
      json: text,
      attachments_source_dir: dir,
    });
  }
  let bytes = std::fs::read(&p).map_err(|e| e.to_string())?;
  let text = String::from_utf8(bytes).map_err(|e| e.to_string())?;
  Ok(BackupSource {
    json: text,
    attachments_source_dir: None,
  })
}

#[tauri::command]
fn restore_attachments_from(app: tauri::AppHandle, source_root_dir: String) -> Result<(), String> {
  if !is_absolute_path(&source_root_dir) {
    return Err("source_root_dir must be absolute".to_string());
  }
  let source = std::path::PathBuf::from(&source_root_dir);
  if !source.exists() {
    return Err("source_root_dir does not exist".to_string());
  }
  let dest_root = attachments_root(&app)?;
  if dest_root.exists() {
    let _ = std::fs::remove_dir_all(&dest_root);
  }
  std::fs::create_dir_all(&dest_root).map_err(|e| e.to_string())?;
  copy_dir_recursive(&source, &dest_root)?;
  Ok(())
}
