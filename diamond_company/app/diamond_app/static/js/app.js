// Diamond Tracker - small progressive enhancements. Every page works without JS.
(function () {
  "use strict";

  // Move focus to the error summary after a failed submit (screen readers
  // announce it; each item links to its field).
  document.addEventListener("DOMContentLoaded", function () {
    var summary = document.querySelector("[data-error-summary]");
    if (summary) summary.focus();

    var autofocus = document.querySelector("[data-autofocus]");
    if (!summary && autofocus) autofocus.focus();
  });

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
  document.addEventListener("DOMContentLoaded", function () { syncToggles(document); });
  document.addEventListener("htmx:afterSwap", function (event) { syncToggles(event.target); });

  // Confirm irreversible actions
  document.addEventListener("submit", function (event) {
    var message = event.target.getAttribute("data-confirm");
    if (message && !window.confirm(message)) event.preventDefault();
  });

  // Print button on the label page
  document.addEventListener("click", function (event) {
    if (event.target.closest("[data-print]")) window.print();
  });
})();
