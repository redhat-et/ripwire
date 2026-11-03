// (#448) A wordless Hono-style registrar: no framework keyword anywhere in this file — the capture,
// not the old text gate, must register the route. (The identifier 'Hono' is not a gate word.)
import { Hono } from 'hono';
const app = new Hono();

app.get('/greet/:name', getGreeting);

export function getGreeting(c: any) {
    return c.text('hello');
}

export default app;
