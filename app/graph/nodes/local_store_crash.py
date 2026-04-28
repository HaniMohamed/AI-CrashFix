from app.services.crash_store import CrashStore

crash_store = CrashStore()

def store_crash(state):
    crash_store.insert_crash(state["crash_id"])
    return state