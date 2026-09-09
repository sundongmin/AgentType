// Parse the official latest-release response without requiring Python or jq.
ObjC.import("Foundation");
function run(argv) {
    if (argv.length !== 1) throw new Error("Expected a release JSON file");
    var data = $.NSData.dataWithContentsOfFile(argv[0]);
    if (!data) throw new Error("Cannot read release JSON");
    var text = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
    var release = JSON.parse(text);
    if (release.draft || release.prerelease || !/^\d+\.\d+\.\d+$/.test(release.tag_name || "")) {
        throw new Error("Unexpected stable-release metadata");
    }
    var version = release.tag_name;
    var name = "Hammerspoon-" + version + ".zip";
    var url = "https://github.com/Hammerspoon/hammerspoon/releases/download/" + version + "/" + name;
    var matches = (release.assets || []).filter(function(asset) {
        return asset.name === name && asset.browser_download_url === url;
    });
    if (matches.length !== 1) throw new Error("Official universal Hammerspoon ZIP not found");
    var digest = matches[0].digest;
    if (typeof digest !== "string" || !/^sha256:[a-f0-9]{64}$/.test(digest)) {
        throw new Error("Release asset has no valid SHA-256 digest");
    }
    return [version, url, digest.slice(7)].join("\n");
}
