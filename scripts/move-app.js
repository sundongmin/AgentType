ObjC.import("Foundation");
function run(argv) {
    if (argv.length !== 2) throw new Error("Expected source and destination paths");
    var error = Ref();
    if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(argv[0], argv[1], error)) {
        throw new Error("Cannot move application into destination: " + ObjC.unwrap(error[0].localizedDescription));
    }
    return "Application installed";
}
