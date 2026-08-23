#include <amxmodx>
#include <amxmisc>
#include <file>
#include <grip>

#define PLUGIN  "OldFrag AntiCheat Updater"
#define VERSION "0.1.0"
#define AUTHOR  "OldFrag"
#define TASK_AUTO_UPDATE 91041
#define BODY_MAX 131071

new const DEFAULT_MANIFEST[] = "https://raw.githubusercontent.com/DmitriySivko/oldfrag-anticheat/main/dist/manifest.json";

new g_manifest_url[256], g_group_url[256], g_expected_sha[65], g_group_name[96];
new g_body[BODY_MAX + 1];
new g_target[256], g_temp[256], g_backup[256], g_state[256];
new g_next_group, g_group_count;
new bool:g_busy;

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);
    register_cvar("ofac_version", VERSION, FCVAR_SERVER | FCVAR_SPONLY);
    bind_pcvar_string(create_cvar("ofac_manifest_url", DEFAULT_MANIFEST), g_manifest_url, charsmax(g_manifest_url));
    register_concmd("ofac_update", "cmd_update", ADMIN_RCON, "- check GitHub database now");
    register_concmd("ofac_status", "cmd_status", ADMIN_RCON, "- show updater state");
}

public plugin_cfg()
{
    new configs[192], basedir[192];
    get_configsdir(configs, charsmax(configs));
    get_basedir(basedir, charsmax(basedir));
    formatex(g_state, charsmax(g_state), "%s/oldfrag_anticheat.state", configs);
    formatex(g_target, charsmax(g_target), "%s/../rechecker/resources.ini", basedir);
    formatex(g_temp, charsmax(g_temp), "%s/../rechecker/resources.ini.new", basedir);
    formatex(g_backup, charsmax(g_backup), "%s/../rechecker/resources.ini.backup", basedir);
    load_state();
    set_task(15.0, "task_update", TASK_AUTO_UPDATE);
}

public cmd_update(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    task_update();
    console_print(id, "[OldFragAC] update request started");
    return PLUGIN_HANDLED;
}

public cmd_status(id, level, cid)
{
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    console_print(id, "[OldFragAC] version=%s busy=%d next_group=%d groups=%d", VERSION, g_busy, g_next_group, g_group_count);
    console_print(id, "[OldFragAC] manifest=%s", g_manifest_url);
    return PLUGIN_HANDLED;
}

public task_update()
{
    if (g_busy) return;
    g_busy = true;
    new GripBody:body = grip_body_from_string("");
    grip_request(g_manifest_url, body, GripRequestTypeGet, "manifest_done");
    grip_destroy_body(body);
}

public manifest_done()
{
    if (!response_ok("manifest")) return 0;
    new error[128];
    new GripJSONValue:root = grip_json_parse_response_body(error, charsmax(error));
    if (root == Invalid_GripJSONValue) return fail_update("invalid manifest JSON");
    new GripJSONValue:groups = grip_json_object_get_value(root, "groups");
    g_group_count = grip_json_array_get_count(groups);
    if (g_group_count <= 0) {
        grip_destroy_json_value(root);
        return fail_update("manifest has no active groups");
    }
    if (g_next_group >= g_group_count) g_next_group = 0;
    new GripJSONValue:item = grip_json_array_get_value(groups, g_next_group);
    grip_json_object_get_string(item, "file", g_group_name, charsmax(g_group_name));
    grip_json_object_get_string(item, "sha256", g_expected_sha, charsmax(g_expected_sha));
    grip_destroy_json_value(root);
    if (!safe_group_name(g_group_name) || strlen(g_expected_sha) != 64)
        return fail_update("unsafe manifest entry");
    formatex(g_group_url, charsmax(g_group_url), "https://raw.githubusercontent.com/DmitriySivko/oldfrag-anticheat/main/dist/%s", g_group_name);
    new GripBody:body = grip_body_from_string("");
    grip_request(g_group_url, body, GripRequestTypeGet, "group_done");
    grip_destroy_body(body);
    return 0;
}

public group_done()
{
    if (!response_ok("group")) return 0;
    new written = grip_get_response_body_string(g_body, charsmax(g_body));
    if (written <= 0 || written >= charsmax(g_body)) return fail_update("empty or oversized group");
    new actual[65];
    hash_string(g_body, Hash_Sha256, actual, charsmax(actual));
    if (!equali(actual, g_expected_sha)) return fail_update("SHA-256 mismatch");

    delete_file(g_temp);
    new fp = fopen(g_temp, "wt");
    if (!fp) return fail_update("cannot write temporary file");
    fputs(fp, g_body);
    fclose(fp);
    hash_file(g_temp, Hash_Sha256, actual, charsmax(actual));
    if (!equali(actual, g_expected_sha)) {
        delete_file(g_temp);
        return fail_update("temporary file verification failed");
    }

    delete_file(g_backup);
    if (file_exists(g_target) && !rename_file(g_target, g_backup, 1)) {
        delete_file(g_temp);
        return fail_update("cannot create backup");
    }
    if (!rename_file(g_temp, g_target, 1)) {
        if (file_exists(g_backup)) rename_file(g_backup, g_target, 1);
        return fail_update("cannot activate database");
    }

    log_amx("Activated %s (%d/%d), applies after map change", g_group_name, g_next_group + 1, g_group_count);
    g_next_group = (g_next_group + 1) % g_group_count;
    save_state();
    g_busy = false;
    return 0;
}

bool:response_ok(const stage[])
{
    if (grip_get_response_state() != GripResponseStateSuccessful || grip_get_response_status_code() != GripHTTPStatusOk) {
        new error[192];
        grip_get_error_description(error, charsmax(error));
        fail_update(error[0] ? error : stage);
        return false;
    }
    return true;
}

fail_update(const reason[])
{
    log_amx("Update rejected: %s", reason);
    g_busy = false;
    return 0;
}

bool:safe_group_name(const value[])
{
    return containi(value, "resources_") == 0 && contain(value, "..") == -1 && contain(value, "/") == -1 && contain(value, "\\") == -1;
}

load_state()
{
    if (!file_exists(g_state)) return;
    new text[16], fp = fopen(g_state, "rt");
    if (fp) { fgets(fp, text, charsmax(text)); fclose(fp); g_next_group = max(0, str_to_num(text)); }
}

save_state()
{
    new fp = fopen(g_state, "wt");
    if (fp) { fprintf(fp, "%d^n", g_next_group); fclose(fp); }
}
