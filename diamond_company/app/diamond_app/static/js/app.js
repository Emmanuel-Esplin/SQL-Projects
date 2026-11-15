// Diamond Tracker - small progressive enhancements. Every page works without JS.
// Loaded without defer (it is tiny) so the "js" class is set before first paint
// and the mobile menu does not flash open.
(function () {
  "use strict";

  document.documentElement.classList.add("js");

  function ready(fn) {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn);
    else fn();
  }

  ready(function () {
    // Move focus to the error summary after a failed submit (screen readers
    // announce it; each item links to its field).
    var summary = document.querySelector("[data-error-summary]");
    if (summary) summary.focus();

    var autofocus = document.querySelector("[data-autofocus]");
    if (!summary && autofocus) autofocus.focus();

    setUpNavToggle();
    setUpPasswordToggles(document);
    syncToggles(document);
  });

  // ------------------------------------------------------------ Mobile menu
  function setUpNavToggle() {
    var button = document.querySelector("[data-nav-toggle]");
    if (!button) return;
    var sidebar = button.closest(".sidebar");
    button.addEventListener("click", function () {
      var open = sidebar.classList.toggle("nav-open");
      button.setAttribute("aria-expanded", open ? "true" : "false");
    });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && sidebar.classList.contains("nav-open")) {
        sidebar.classList.remove("nav-open");
        button.setAttribute("aria-expanded", "false");
        button.focus();
      }
    });
  }

  // ----------------------------------------------------- Show/hide password
  // Lets people check what they typed; password managers and paste still work.
  function setUpPasswordToggles(root) {
    root.querySelectorAll("input[type='password'][data-reveal]").forEach(function (input) {
      if (input.parentNode.classList.contains("password-field")) return;
      var wrapper = document.createElement("div");
      wrapper.className = "password-field";
      input.parentNode.insertBefore(wrapper, input);
      wrapper.appendChild(input);

      var button = document.createElement("button");
      button.type = "button";
      button.className = "btn btn-secondary";
      button.textContent = "Show";
      button.setAttribute("aria-controls", input.id);
      button.setAttribute("aria-pressed", "false");
      button.setAttribute("aria-label", "Show password");
      button.addEventListener("click", function () {
        var show = input.type === "password";
        input.type = show ? "text" : "password";
        button.textContent = show ? "Hide" : "Show";
        button.setAttribute("aria-pressed", show ? "true" : "false");
        button.setAttribute("aria-label", show ? "Hide password" : "Show password");
        input.focus();
      });
      wrapper.appendChild(button);
    });
  }

  // ------------------------------------------------- Conditional form fields
  // Show only the fields that apply: fancy hue/intensity vs D-Z color,
  // grades on check-in only when "mark as polished" is ticked.
  function syncToggles(root) {
    root.querySelectorAll("[data-show-when]").forEach(function (el) {
      var parts = el.getAttribute("data-show-when").split("=");
      var form = el.closest("form") || document;
      var control = form.querySelector("[name='" + parts[0] + "']:checked") ||
                    form.querySelector("select[name='" + parts[0] + "']");
      var value = control ? (control.type === "checkbox" ? (control.checked ? "on" : "") : control.value) : "";
      var show = parts[1].split("|").indexOf(value) !== -1;
      el.hidden = !show;
      el.querySelectorAll("input, select, textarea").forEach(function (input) {
        input.disabled = !show;
      });
    });
  }
  document.addEventListener("change", function () { syncToggles(document); });
  document.addEventListener("htmx:afterSwap", function (event) {
    syncToggles(event.target);
    setUpPasswordToggles(event.target);
  });

  // ------------------------------------------------------------- Submitting
  // Confirm irreversible actions, then lock the button so a slow network or
  // a double click cannot record the same safe movement twice.
  document.addEventListener("submit", function (event) {
    var form = event.target;
    var message = form.getAttribute("data-confirm");
    if (message && !window.confirm(message)) {
      event.preventDefault();
      return;
    }
    if (event.defaultPrevented || form.method.toLowerCase() !== "post") return;
    var button = event.submitter || form.querySelector("button[type='submit'], button:not([type])");
    if (!button) return;
    // Disable after the browser has read the form, so the button's own
    // name/value is still sent
    window.setTimeout(function () {
      button.disabled = true;
      button.classList.add("is-busy");
      button.setAttribute("aria-busy", "true");
    }, 0);
  });

  // Coming back with the Back button restores the page from cache: unlock it
  window.addEventListener("pageshow", function (event) {
    if (!event.persisted) return;
    document.querySelectorAll(".is-busy").forEach(function (button) {
      button.disabled = false;
      button.classList.remove("is-busy");
      button.removeAttribute("aria-busy");
    });
  });

  // ---------------------------------------------------------- HTMX loading
  document.addEventListener("htmx:beforeRequest", function (event) {
    var target = event.detail.target;
    if (target) target.setAttribute("aria-busy", "true");
  });
  document.addEventListener("htmx:afterRequest", function (event) {
    var target = event.detail.target;
    if (target) target.removeAttribute("aria-busy");
  });

  // Print button on the label page
  document.addEventListener("click", function (event) {
    if (event.target.closest("[data-print]")) window.print();
  });
})();
