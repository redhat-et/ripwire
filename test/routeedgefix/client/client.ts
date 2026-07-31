// Tiny fetch/axios client fixture for the B6.3 HTTP-route edge gate (test/routeedgecheck.sh).
import axios from 'axios';

export async function loadUser() {
    return fetch('/users/42');                    // template-path match -> GET /users/{user_id} (get_user)
}

export async function registerUser() {
    return axios.post('/users', {});               // exact literal match -> POST /users (create_user)
}

export async function loadOrder() {
    return axios.get('/orders/7');                  // template-path match -> GET /orders/{order_id} (get_order)
}

export async function loadItem() {
    return fetch('/items/42');                      // AMBIGUOUS shape (matches BOTH item DEFs) -> NO edge
}

export async function loadNothing() {
    return fetch('/does-not-exist');                 // no matching DEF -> unresolved, NO edge
}

export async function loadWidget() {
    return fetch('/widgets/7');                      // matches the JS server DEF in the sibling file -> getWidget
}

export async function loadDynamic(id: string) {
    return fetch(`/users/${id}`);                     // template literal path -> KNOWN LIMITATION, not detected
}
