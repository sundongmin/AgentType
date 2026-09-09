// Read-only macOS Text Input Source Services query. Run with osascript -l JavaScript.
// No Hammerspoon IPC, input-source selection, or preference writes.
ObjC.import("Carbon");
// CFArrayGetValueAtIndex yields void*. Rebind the property accessor so JXA can
// pass that pointer without an incompatible opaque TISInputSourceRef conversion.
ObjC.bindFunction("TISGetInputSourceProperty", ["void *", ["void *", "void *"]]);

function readProperty(source, key) {
    return ObjC.deepUnwrap(ObjC.castRefToObject($.TISGetInputSourceProperty(source, key)));
}
function cleanName(value) {
    return String(value || "").replace(/[\x00-\x1f\x7f-\x9f]/g, " ");
}
function run(argv) {
    if (argv.length > 1 || (argv.length === 1 && argv[0] !== "--all")) {
        throw new Error("Usage: input-sources.js [--all]");
    }
    var all = argv[0] === "--all";
    var sources = $.TISCreateInputSourceList(null, false);
    var count = Number($.CFArrayGetCount(sources));
    if (!count) throw new Error("无法读取系统输入源列表，请在登录的 macOS 用户会话中重试。");
    var keyboardCategory = ObjC.unwrap(ObjC.castRefToObject($.kTISCategoryKeyboardInputSource));
    var seen = {}, result = [];
    for (var index = 0; index < count; index++) {
        var source = $.CFArrayGetValueAtIndex(sources, index);
        if (!readProperty(source, $.kTISPropertyInputSourceIsSelectCapable)) continue;
        if (!readProperty(source, $.kTISPropertyInputSourceIsEnabled)) continue;
        if (readProperty(source, $.kTISPropertyInputSourceCategory) !== keyboardCategory) continue;
        var languages = readProperty(source, $.kTISPropertyInputSourceLanguages) || [];
        var chinese = languages.some(function (language) {
            return /^(zh|yue|cmn)([-_]|$)/i.test(language);
        });
        if (!all && !chinese) continue;
        var id = readProperty(source, $.kTISPropertyInputSourceID);
        if (typeof id !== "string" || !/^[a-zA-Z0-9._-]+$/.test(id) || seen[id]) continue;
        seen[id] = true;
        var name = cleanName(readProperty(source, $.kTISPropertyLocalizedName)) || id;
        result.push([id, name, chinese ? "chinese" : "other"].join("\t"));
    }
    return result.join("\n");
}
