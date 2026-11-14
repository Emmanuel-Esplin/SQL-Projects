"""Password policy, hashing, throttling, sessions and redirects (no database)."""

import pytest

from diamond_app import security
from diamond_app.routers.auth import safe_next


@pytest.mark.parametrize(("password", "username", "fragment"), [
    ("short", None, "at least 12"),
    ("x" * 129, None, "at most 128"),
    ("password1234", None, "too easy"),
    ("PASSWORD1234", None, "too easy"),
    ("aaaaaaaaaaaaaa", None, "too easy"),
    ("abababababab", None, "too easy"),
    ("my-name-is-keeper", "keeper", "username"),
])
def test_password_problem_rejects(password, username, fragment):
    assert fragment in security.password_problem(password, username)


@pytest.mark.parametrize("password", ["correct-horse-battery-staple", "plum orbit candle harbor", "x" * 3 + "yz12" * 3])
def test_password_problem_accepts(password):
    assert security.password_problem(password, "keeper") is None


def test_short_username_is_not_matched_inside_passwords():
    assert security.password_problem("Al-is-fine-here-ok", "al") is None


def test_hash_and_verify():
    hashed = security.hash_password("plum orbit candle harbor")
    assert hashed.startswith("$argon2id$")
    assert security.verify_password(hashed, "plum orbit candle harbor")
    assert not security.verify_password(hashed, "plum orbit candle harbo")
    assert not security.verify_password("not-a-hash", "anything")


def test_throttle_blocks_after_limit_and_expires(monkeypatch):
    clock = [1000.0]
    monkeypatch.setattr(security.time, "monotonic", lambda: clock[0])
    throttle = security.LoginThrottle(max_failures=3, window_s=60)
    for _ in range(2):
        throttle.record("k")
    assert not throttle.blocked("k")
    throttle.record("k")
    assert throttle.blocked("k")
    assert not throttle.blocked("other")
    clock[0] += 61
    assert not throttle.blocked("k")
    assert "k" not in throttle._hits  # expired keys are dropped


def test_throttle_memory_is_bounded():
    throttle = security.LoginThrottle(max_failures=3, window_s=60, max_keys=100)
    for n in range(1000):
        throttle.record(f"user-{n}")
    assert len(throttle._hits) == 100
    assert "user-999" in throttle._hits and "user-0" not in throttle._hits


def test_throttle_clear():
    throttle = security.LoginThrottle(max_failures=1, window_s=60)
    throttle.record("k")
    assert throttle.blocked("k")
    throttle.clear("k")
    assert not throttle.blocked("k")


def test_login_locked_checks_username_and_address():
    try:
        for n in range(5):
            security.record_login_failure("Keeper", f"192.0.2.{n}")
        assert security.login_locked("keeper", "198.51.100.9")  # same user, any address, case-insensitive
        security.clear_login_failures("KEEPER")
        assert not security.login_locked("keeper", "198.51.100.9")
        for n in range(20):
            security.record_login_failure(f"user{n}", "198.51.100.1")
        assert security.login_locked("someone-new", "198.51.100.1")
    finally:
        security._by_username._hits.clear()
        security._by_address._hits.clear()


def test_session_fingerprint_changes_with_password_hash():
    a = security.session_fingerprint("$argon2id$hash-one")
    assert a == security.session_fingerprint("$argon2id$hash-one")
    assert a != security.session_fingerprint("$argon2id$hash-two")
    assert len(a) == 32


def test_log_value_strips_control_characters():
    assert security.log_value("bob\r\nINFO forged entry") == "bob??INFO forged entry"
    assert len(security.log_value("x" * 500)) == 64


def test_roles():
    admin = security.CurrentUser(1, "a", "A", security.ADMIN, None)
    polisher = security.CurrentUser(2, "p", "P", security.POLISHER, 7)
    assert admin.has(security.SALES) and admin.has()
    assert polisher.has(security.POLISHER) and not polisher.has(security.SALES) and not polisher.has()
    assert admin.sees_prices and not polisher.sees_prices


@pytest.mark.parametrize(("target", "expected"), [
    ("/diamonds?status=SOLD", "/diamonds?status=SOLD"),
    ("/", "/"),
    ("//evil.example", "/"),
    ("/\\evil.example", "/"),
    ("/\t/evil.example", "/"),
    ("/\n/evil.example", "/"),
    ("/ /evil.example", "/"),
    ("https://evil.example", "/"),
    ("javascript:alert(1)", "/"),
    ("diamonds", "/"),
    ("/" + "a" * 3000, "/"),
])
def test_safe_next(target, expected):
    assert safe_next(target) == expected
