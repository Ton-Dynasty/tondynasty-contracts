trait Lockable {
    is_locked: Bool;

    virtual inline fun lock() {
        self.is_locked = true;
    }

    virtual inline fun unlock() {
        self.is_locked = false;
    }

    virtual inline fun ensureLocked() {
        require(self.is_locked, "Lockable: Object is not locked");
    }

    virtual inline fun ensureUnlocked() {
        require(!self.is_locked, "Lockable: Object is locked");
    }

    get fun is_locked(): Bool {
        return self.is_locked;
    }
}
