require('dotenv').config();
const express = require('express');
const session = require('express-session');
const path = require('path');
const { exec } = require('child_process');

const app = express();
const PORT = process.env.PORT || 3000;

// View engine
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Middleware
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
app.use(session({
    secret: process.env.SESSION_SECRET || 'default-secret',
    resave: false,
    saveUninitialized: false,
    cookie: { maxAge: 1000 * 60 * 60 * 4 } // 4 hours
}));

// Script paths
const SCRIPT_DIR = __dirname;
const SCRIPTS = {
    addUser: path.join(SCRIPT_DIR, 'add-user.sh'),
    delUser: path.join(SCRIPT_DIR, 'del-user.sh'),
    showUser: path.join(SCRIPT_DIR, 'show-user.sh'),
    routeUser: path.join(SCRIPT_DIR, 'route-user.sh'),
};

// Auth middleware
function requireAuth(req, res, next) {
    if (req.session && req.session.authenticated) {
        return next();
    }
    res.redirect('/login');
}

// Helper: run shell command
function runScript(command) {
    return new Promise((resolve, reject) => {
        exec(command, { timeout: 30000 }, (error, stdout, stderr) => {
            // Strip ANSI color codes
            const cleanOutput = (stdout || '').replace(/\x1b\[[0-9;]*m/g, '');
            const cleanError = (stderr || '').replace(/\x1b\[[0-9;]*m/g, '');
            if (error) {
                resolve({ success: false, output: cleanOutput, error: cleanError || error.message });
            } else {
                resolve({ success: true, output: cleanOutput, error: cleanError });
            }
        });
    });
}

// Helper: parse show-user output
function parseShowUserOutput(raw) {
    const lines = raw.split('\n');
    const activeUsers = [];
    const registeredUsers = [];
    let section = 'none';
    let currentUser = null;

    for (const line of lines) {
        const trimmed = line.trim();

        // Detect Active Users section
        if (trimmed.includes('OpenVPN Active Users')) {
            section = 'active';
            continue;
        }
        if (trimmed.includes('Registered Users (CCD)')) {
            section = 'registered';
            continue;
        }

        if (section === 'active') {
            if (trimmed.startsWith('User') && trimmed.includes(':')) {
                currentUser = { subnets: [] };
                currentUser.name = trimmed.split(':').slice(1).join(':').trim();
            }
            if (currentUser && trimmed.startsWith('Real IP') && trimmed.includes(':')) {
                currentUser.realIp = trimmed.split(':').slice(1).join(':').trim();
            }
            if (currentUser && trimmed.startsWith('VPN IP') && trimmed.includes(':')) {
                currentUser.vpnIp = trimmed.split(':').slice(1).join(':').trim();
            }
            if (currentUser && trimmed.startsWith('Connected') && trimmed.includes(':')) {
                currentUser.connected = trimmed.split(':').slice(1).join(':').trim();
            }
            if (currentUser && trimmed.startsWith('RX / TX') && trimmed.includes(':')) {
                currentUser.traffic = trimmed.split(':').slice(1).join(':').trim();
            }
            if (currentUser && trimmed.includes('/') && (trimmed.includes('255.') || trimmed.includes('128.'))) {
                currentUser.subnets.push(trimmed.replace(/🔀/g, '').trim());
            }
            if (currentUser && trimmed.startsWith('└')) {
                activeUsers.push(currentUser);
                currentUser = null;
            }
        }

        if (section === 'registered') {
            const onlineMatch = trimmed.match(/ONLINE\s+(.+)/);
            const offlineMatch = trimmed.match(/OFFLINE\s+(.+)/);
            if (onlineMatch) {
                currentUser = { name: onlineMatch[1].trim(), status: 'online', subnets: [] };
                registeredUsers.push(currentUser);
            } else if (offlineMatch) {
                currentUser = { name: offlineMatch[1].trim(), status: 'offline', subnets: [] };
                registeredUsers.push(currentUser);
            } else if (currentUser && trimmed.includes('└─') && trimmed.includes('/')) {
                currentUser.subnets.push(trimmed.replace('└─', '').trim());
            }
        }
    }

    return { activeUsers, registeredUsers };
}

// Helper: list CCD users (fallback)
function listCcdUsers() {
    return new Promise((resolve, reject) => {
        exec('ls /etc/openvpn/ccd 2>/dev/null', (error, stdout) => {
            if (error) {
                resolve([]);
            } else {
                const users = stdout.trim().split('\n').filter(u => u.length > 0);
                resolve(users);
            }
        });
    });
}

// Helper: get user routes from CCD
function getUserRoutes(username) {
    return new Promise((resolve) => {
        exec(`cat /etc/openvpn/ccd/${username} 2>/dev/null`, (error, stdout) => {
            if (error) {
                resolve([]);
            } else {
                const routes = [];
                stdout.split('\n').forEach(line => {
                    if (line.startsWith('iroute')) {
                        const parts = line.split(/\s+/);
                        routes.push({ network: parts[1], mask: parts[2] });
                    }
                });
                resolve(routes);
            }
        });
    });
}

// ==============================
// ROUTES
// ==============================

// Login page
app.get('/login', (req, res) => {
    if (req.session && req.session.authenticated) {
        return res.redirect('/');
    }
    res.render('login', { error: null });
});

app.post('/login', (req, res) => {
    const { username, password } = req.body;
    if (username === process.env.ADMIN_USER && password === process.env.ADMIN_PASS) {
        req.session.authenticated = true;
        req.session.username = username;
        res.redirect('/');
    } else {
        res.render('login', { error: 'Username atau password salah!' });
    }
});

app.get('/logout', (req, res) => {
    req.session.destroy();
    res.redirect('/login');
});

// Dashboard
app.get('/', requireAuth, async (req, res) => {
    try {
        const result = await runScript(`bash "${SCRIPTS.showUser}"`);
        const parsed = parseShowUserOutput(result.output);
        res.render('dashboard', {
            user: req.session.username,
            activeUsers: parsed.activeUsers,
            registeredUsers: parsed.registeredUsers,
            rawOutput: result.output,
            page: 'dashboard'
        });
    } catch (err) {
        res.render('dashboard', {
            user: req.session.username,
            activeUsers: [],
            registeredUsers: [],
            rawOutput: 'Error fetching data: ' + err.message,
            page: 'dashboard'
        });
    }
});

// Add User Page
app.get('/add-user', requireAuth, (req, res) => {
    res.render('add-user', { user: req.session.username, result: null, page: 'add-user' });
});

app.post('/add-user', requireAuth, async (req, res) => {
    const { username, subnets } = req.body;
    if (!username) {
        return res.render('add-user', {
            user: req.session.username,
            result: { success: false, output: '', error: 'Username tidak boleh kosong!' },
            page: 'add-user'
        });
    }

    const cmd = subnets && subnets.trim()
        ? `bash "${SCRIPTS.addUser}" "${username}" ${subnets.trim()}`
        : `bash "${SCRIPTS.addUser}" "${username}"`;

    const result = await runScript(cmd);
    res.render('add-user', { user: req.session.username, result, page: 'add-user' });
});

// Delete User Page
app.get('/del-user', requireAuth, async (req, res) => {
    const users = await listCcdUsers();
    res.render('del-user', { user: req.session.username, users, result: null, page: 'del-user' });
});

app.post('/del-user', requireAuth, async (req, res) => {
    const { username } = req.body;
    if (!username) {
        const users = await listCcdUsers();
        return res.render('del-user', {
            user: req.session.username, users,
            result: { success: false, output: '', error: 'Username tidak boleh kosong!' },
            page: 'del-user'
        });
    }

    const result = await runScript(`bash "${SCRIPTS.delUser}" "${username}"`);
    const users = await listCcdUsers();
    res.render('del-user', { user: req.session.username, users, result, page: 'del-user' });
});

// Show Users Page
app.get('/show-users', requireAuth, async (req, res) => {
    const result = await runScript(`bash "${SCRIPTS.showUser}"`);
    const parsed = parseShowUserOutput(result.output);
    res.render('show-users', {
        user: req.session.username,
        activeUsers: parsed.activeUsers,
        registeredUsers: parsed.registeredUsers,
        rawOutput: result.output,
        page: 'show-users'
    });
});

// Route Management Page
app.get('/routes', requireAuth, async (req, res) => {
    const users = await listCcdUsers();
    res.render('routes', { user: req.session.username, users, result: null, routes: null, selectedUser: '', page: 'routes' });
});

app.post('/routes/add', requireAuth, async (req, res) => {
    const { username, subnets } = req.body;
    const result = await runScript(`bash "${SCRIPTS.routeUser}" add "${username}" ${subnets}`);
    const users = await listCcdUsers();
    res.render('routes', { user: req.session.username, users, result, routes: null, selectedUser: username, page: 'routes' });
});

app.post('/routes/remove', requireAuth, async (req, res) => {
    const { username, subnets } = req.body;
    const result = await runScript(`bash "${SCRIPTS.routeUser}" remove "${username}" ${subnets}`);
    const users = await listCcdUsers();
    res.render('routes', { user: req.session.username, users, result, routes: null, selectedUser: username, page: 'routes' });
});

app.post('/routes/list', requireAuth, async (req, res) => {
    const { username } = req.body;
    const routes = await getUserRoutes(username);
    const users = await listCcdUsers();
    res.render('routes', { user: req.session.username, users, result: null, routes, selectedUser: username, page: 'routes' });
});

// API: Refresh users (for AJAX)
app.get('/api/users', requireAuth, async (req, res) => {
    const result = await runScript(`bash "${SCRIPTS.showUser}"`);
    const parsed = parseShowUserOutput(result.output);
    res.json(parsed);
});

app.get('/api/ccd-users', requireAuth, async (req, res) => {
    const users = await listCcdUsers();
    res.json(users);
});

app.get('/api/routes/:username', requireAuth, async (req, res) => {
    const routes = await getUserRoutes(req.params.username);
    res.json(routes);
});

// Start server
app.listen(PORT, () => {
    console.log(`\n  🌐 OpenVPN Management Panel`);
    console.log(`  📡 Running on http://localhost:${PORT}`);
    console.log(`  👤 Login: ${process.env.ADMIN_USER} / ${'*'.repeat(process.env.ADMIN_PASS.length)}\n`);
});
