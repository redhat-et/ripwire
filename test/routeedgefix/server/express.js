// Tiny Express server fixture for the B6.3 HTTP-route edge gate (test/routeedgecheck.sh).
const express = require('express');
const app = express();

app.get('/widgets/:widgetId', getWidget);

function getWidget(req, res) {
    res.send('widget');
}

module.exports = app;
