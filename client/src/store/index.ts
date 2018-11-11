import { session } from "./modules/session";
import { RootState } from "./types";

import Vue from "vue";
import Vuex, { StoreOptions } from "vuex";

Vue.use(Vuex);

const store: StoreOptions<RootState> = {
    state: {},
    modules: {
        session,
    }
};

export default new Vuex.Store<RootState>(store);