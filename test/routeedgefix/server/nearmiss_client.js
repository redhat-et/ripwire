// a client call with a string first arg and a function second arg:
// must NOT register a route (axios.get with config callback)
const axios = require('axios');
function fetchData() {
    return axios.get('/api/data', (response) => response.data);
}
module.exports = { fetchData };
