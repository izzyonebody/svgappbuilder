import axios from "axios";

const BASE = "http://127.0.0.1:8000";

export default {
  generate: (data) => axios.post(`${BASE}/api/generate/`, data).then(r => r.data),
  search: (data) => axios.post(`${BASE}/api/search/`, data).then(r => r.data)
};
