// Host-only integration probe of Fedora GDM's real worker and PAM conversation.
const {Gio, GLib} = imports.gi;
const loop = new GLib.MainLoop(null, false);
const xml = `<node><interface name="org.gnome.DisplayManager.WorkerManager">
<method name="Hello"/>
<method name="InfoQuery"><arg direction="in" type="s"/><arg direction="in" type="s"/><arg direction="out" type="s"/></method>
<method name="SecretInfoQuery"><arg direction="in" type="s"/><arg direction="in" type="s"/><arg direction="out" type="s"/></method>
<method name="Info"><arg direction="in" type="s"/><arg direction="in" type="s"/></method>
<method name="Problem"><arg direction="in" type="s"/><arg direction="in" type="s"/></method>
</interface></node>`;
let connection, exported, child, failed = false, secrets = 0;
const newPassword = `GdmTest9!${GLib.uuid_string_random()}`;
function fail(e) { printerr(`${e}`); failed = true; loop.quit(); }
function call(method, parameters, callback) {
    connection.call(null, '/org/gnome/DisplayManager/Worker', 'org.gnome.DisplayManager.Worker', method,
        parameters, null, Gio.DBusCallFlags.NONE, 45000, null, (c, r) => {
            try { c.call_finish(r); print(`Worker ${method}: success`); callback(); } catch(e) { fail(e); }
        });
}
const details = {'service':new GLib.Variant('s','gdm-password'), 'username':new GLib.Variant('s','senemos'),
    'is-program-session':new GLib.Variant('b',false), 'display-is-local':new GLib.Variant('b',true),
    'display-is-initial':new GLib.Variant('b',false), 'console':new GLib.Variant('s','/dev/tty99'),
    'seat-id':new GLib.Variant('s','seat0'), 'hostname':new GLib.Variant('s','')};
const manager = {
    Hello() { GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        call('Initialize', new GLib.Variant('(a{sv})',[details]), () =>
            call('Authenticate', null, () => call('Authorize', null, () => {
                if (secrets < 3) { fail('Password change prompts were not observed'); return; }
                print('GDM real worker completed expired-password change through PAM'); loop.quit();
            })));
        return GLib.SOURCE_REMOVE;
    }); },
    InfoQuery(service, query) { print(`InfoQuery: ${query}`); return 'senemos'; },
    SecretInfoQuery(service, query) {
        print(`SecretInfoQuery: ${query}`); secrets++;
        if (/new.*password|retype|repeat/i.test(query)) return newPassword;
        return 'fedora';
    },
    Info(service, message) { print(`Info: ${message}`); },
    Problem(service, message) { print(`Problem: ${message}`); },
};
const server = Gio.DBusServer.new_sync('unix:tmpdir=/tmp', Gio.DBusServerFlags.NONE, Gio.dbus_generate_guid(), null, null);
server.connect('new-connection', (s,c) => {
    connection = c;
    exported = Gio.DBusExportedObject.wrapJSObject(xml, manager);
    exported.export(c, '/org/gnome/DisplayManager/Session');
    return true;
});
server.start();
const launcher = new Gio.SubprocessLauncher({flags:Gio.SubprocessFlags.STDIN_INHERIT});
launcher.setenv('GDM_SESSION_DBUS_ADDRESS',server.get_client_address(),true);
launcher.setenv('LANG','C.UTF-8',true);
child = launcher.spawnv(['/usr/libexec/gdm-session-worker']);
GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT,60,()=>{fail('GDM worker timed out');return GLib.SOURCE_REMOVE;});
loop.run(); child.force_exit(); child.wait(null); server.stop();
if (failed) imports.system.exit(1);
