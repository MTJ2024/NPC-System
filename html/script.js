console.log("NPC Dashboard JS geladen!");

const resourceName = (typeof GetParentResourceName === "function") ? GetParentResourceName() : "npc_dashboard";

fetch("https://" + resourceName + "/htmlGeladen", { method: "POST" });

/* ===== NPC Type Definitions (synced with server) ===== */
const npcTypes = [
  { name: "Polizist", model: "s_m_y_cop_01", weapon: "WEAPON_PISTOL", behavior: "Wache", radius: 15, category: "law" },
  { name: "Sheriff", model: "s_m_y_sheriff_01", weapon: "WEAPON_PISTOL", behavior: "Wache", radius: 15, category: "law" },
  { name: "Gangmitglied", model: "g_m_y_ballaeast_01", weapon: "WEAPON_MICROSMG", behavior: "Aggressiv", radius: 10, category: "criminal" },
  { name: "Mafia", model: "g_m_m_chicold_01", weapon: "WEAPON_PISTOL", behavior: "Aggressiv", radius: 10, category: "criminal" },
  { name: "Dealer", model: "g_m_y_mexgoon_01", weapon: "WEAPON_PISTOL", behavior: "Neutral", radius: 10, category: "criminal" },
  { name: "Sicherheitskraft", model: "s_m_m_security_01", weapon: "WEAPON_PISTOL", behavior: "Wache", radius: 15, category: "security" },
  { name: "Türsteher", model: "s_m_m_bouncer_01", weapon: "WEAPON_BAT", behavior: "Wache", radius: 10, category: "security" },
  { name: "Koch mit Messer", model: "s_m_y_chef_01", weapon: "WEAPON_KNIFE", behavior: "Passiv", radius: 8, category: "civilian" },
  { name: "Pilot mit Pistole", model: "s_m_m_pilot_01", weapon: "WEAPON_PISTOL", behavior: "Neutral", radius: 10, category: "civilian" },
  { name: "Mechaniker mit Schraubenschlüssel", model: "s_m_m_autoshop_01", weapon: "WEAPON_WRENCH", behavior: "Neutral", radius: 8, category: "civilian" },
  { name: "Geschäftsmann", model: "a_m_m_business_01", weapon: "", behavior: "Passiv", radius: 8, category: "civilian" },
  { name: "VIP", model: "a_m_y_business_01", weapon: "", behavior: "Neutral", radius: 8, category: "civilian" },
  { name: "Sanitäter", model: "s_m_m_paramedic_01", weapon: "", behavior: "Passiv", radius: 10, category: "emergency" },
  { name: "Feuerwehrmann", model: "s_m_y_fireman_01", weapon: "", behavior: "Passiv", radius: 10, category: "emergency" },
  { name: "Taxifahrer", model: "s_m_m_taxi_01", weapon: "", behavior: "Passiv", radius: 8, category: "civilian" },
  { name: "Obdachloser", model: "a_m_m_tramp_01", weapon: "", behavior: "Passiv", radius: 8, category: "civilian" },
  { name: "Jogger", model: "a_m_y_jogger_01", weapon: "", behavior: "Passiv", radius: 8, category: "civilian" },
  { name: "Bauarbeiter", model: "s_m_y_construct_01", weapon: "", behavior: "Neutral", radius: 10, category: "civilian" },
  { name: "Arzt", model: "s_m_m_doctor_01", weapon: "", behavior: "Passiv", radius: 10, category: "emergency" },
  { name: "Landwirt", model: "a_m_m_farmer_01", weapon: "", behavior: "Passiv", radius: 10, category: "civilian" },
  { name: "Army", model: "s_m_y_marine_03", weapon: "WEAPON_CARBINERIFLE", behavior: "Aggressiv", radius: 20, category: "military" }
];

const weaponList = [
  { label: "Keine Waffe", value: "" },
  { label: "Pistole", value: "WEAPON_PISTOL" },
  { label: "Maschinenpistole", value: "WEAPON_MICROSMG" },
  { label: "Karabiner", value: "WEAPON_CARBINERIFLE" },
  { label: "Messer", value: "WEAPON_KNIFE" },
  { label: "Schläger", value: "WEAPON_BAT" },
  { label: "Schraubenschlüssel", value: "WEAPON_WRENCH" }
];

const behaviorList = [
  { label: "Passiv", value: "Passiv" },
  { label: "Neutral", value: "Neutral" },
  { label: "Wache", value: "Wache" },
  { label: "Aggressiv", value: "Aggressiv" }
];

const categoryMap = {
  law: { label: "Strafverfolgung", icon: "fa-shield-halved", color: "cat-law" },
  criminal: { label: "Kriminelle", icon: "fa-skull-crossbones", color: "cat-criminal" },
  security: { label: "Sicherheit", icon: "fa-user-shield", color: "cat-security" },
  military: { label: "Militär", icon: "fa-jet-fighter", color: "cat-military" },
  emergency: { label: "Rettungsdienste", icon: "fa-truck-medical", color: "cat-emergency" },
  civilian: { label: "Zivilisten", icon: "fa-person-walking", color: "cat-civilian" }
};

const behaviorIcons = {
  "Aggressiv": "fa-skull",
  "Wache": "fa-shield-halved",
  "Neutral": "fa-scale-balanced",
  "Passiv": "fa-dove"
};

const weaponLabels = {};
weaponList.forEach(w => { weaponLabels[w.value] = w.label; });

/* ===== State ===== */
let npcList = [];
let editNPC = null;
let createPending = null;
let activePanel = "overview";
let activeCategory = null;
let searchQuery = "";
let focusState = true;

/* ===== DOM Ready ===== */
document.addEventListener("DOMContentLoaded", function() {
  const dashboardUI = document.getElementById("npc-dashboard-ui");
  const sidebarNav = document.getElementById("sidebar-nav");
  const topbarTitle = document.getElementById("topbar-title");
  const searchBox = document.getElementById("search-box");
  const searchInput = document.getElementById("search-input");
  const overviewPanel = document.getElementById("overview-panel");
  const npcListPanel = document.getElementById("npc-list-panel");
  const npcCreatePanel = document.getElementById("npc-create-panel");
  const npcCardsGrid = document.getElementById("npc-cards-grid");
  const emptyState = document.getElementById("empty-state");
  const catFilterPills = document.getElementById("cat-filter-pills");
  const npcTypeSelect = document.getElementById("npc-type-select");
  const npcModel = document.getElementById("npc-model");
  const npcWeapon = document.getElementById("npc-weapon");
  const npcBehavior = document.getElementById("npc-behavior");
  const npcRadius = document.getElementById("npc-radius");
  const npcHeading = document.getElementById("npc-heading");
  const npcMovement = document.getElementById("npc-movement");
  const npcIgnoreGroups = document.getElementById("npc-ignore-groups");
  const npcIgnoreJobs = document.getElementById("npc-ignore-jobs");
  const npcCreateBtn = document.getElementById("npc-create-btn");
  const npcSaveBtn = document.getElementById("npc-save-btn");
  const npcCancelBtn = document.getElementById("npc-cancel-edit-btn");
  const closeBtn = document.getElementById("close-btn");
  const formHeader = document.getElementById("form-header");
  const mousePickOverlay = document.getElementById("mouse-pick-overlay");
  const overlay = document.getElementById("overlay");

  const panels = { overview: overviewPanel, "npc-list": npcListPanel, "npc-create": npcCreatePanel };

  /* ===== Utility ===== */
  function setNuiFocus(enable) {
    focusState = !!enable;
    if (typeof window.invokeNative === "function") {
      window.invokeNative("setNuiFocus", enable, enable);
    }
  }

  function showToast(msg, type) {
    type = type || "info";
    const container = document.getElementById("toast-container");
    const toast = document.createElement("div");
    const icons = { success: "fa-circle-check", error: "fa-circle-xmark", info: "fa-circle-info" };
    toast.className = "toast toast-" + type;
    toast.innerHTML = '<i class="fa-solid ' + (icons[type] || icons.info) + ' toast-icon"></i><span class="toast-msg">' + msg + '</span>';
    container.appendChild(toast);
    setTimeout(function() {
      toast.classList.add("removing");
      setTimeout(function() { toast.remove(); }, 300);
    }, 3000);
  }

  function getNpcCategory(npc) {
    var t = npcTypes.find(function(tp) { return tp.model === npc.model; });
    return t ? t.category : "civilian";
  }

  function isMoving(npc) {
    return npc.movement === 1 || npc.movement === true || npc.movement === "1";
  }

  function escapeHtml(text) {
    if (!text) return "";
    var div = document.createElement("div");
    div.appendChild(document.createTextNode(text));
    return div.innerHTML;
  }

  /* ===== Navigation ===== */
  function switchPanel(panelId, category) {
    activePanel = panelId;
    activeCategory = category || null;
    Object.keys(panels).forEach(function(key) {
      panels[key].classList.toggle("active", key === panelId);
    });
    sidebarNav.querySelectorAll(".nav-item").forEach(function(btn) {
      var btnPanel = btn.getAttribute("data-panel");
      var btnCat = btn.getAttribute("data-category");
      btn.classList.toggle("active", btnPanel === panelId && (btnCat || null) === activeCategory);
    });
    searchBox.style.display = panelId === "npc-list" ? "flex" : "none";
    if (panelId === "overview") {
      topbarTitle.textContent = "Übersicht";
      renderOverview();
    } else if (panelId === "npc-list") {
      topbarTitle.textContent = activeCategory ? categoryMap[activeCategory].label : "Alle NPCs";
      renderNpcCards();
    } else if (panelId === "npc-create") {
      topbarTitle.textContent = editNPC ? "NPC bearbeiten" : "NPC erstellen";
      updateFormMode();
    }
  }

  sidebarNav.addEventListener("click", function(e) {
    var btn = e.target.closest(".nav-item");
    if (!btn) return;
    var panel = btn.getAttribute("data-panel");
    var cat = btn.getAttribute("data-category");
    if (panel === "npc-create") {
      editNPC = null;
      resetForm();
    }
    switchPanel(panel, cat);
  });

  /* ===== Stats & Overview ===== */
  function updateStats() {
    var total = npcList.length;
    var aggressive = 0, wache = 0, passive = 0, neutral = 0, moving = 0;
    var catCounts = { law: 0, criminal: 0, security: 0, military: 0, emergency: 0, civilian: 0 };

    npcList.forEach(function(npc) {
      if (npc.behavior === "Aggressiv") aggressive++;
      else if (npc.behavior === "Wache") wache++;
      else if (npc.behavior === "Passiv") passive++;
      else if (npc.behavior === "Neutral") neutral++;
      if (isMoving(npc)) moving++;
      var cat = getNpcCategory(npc);
      if (catCounts[cat] !== undefined) catCounts[cat]++;
    });

    document.getElementById("stat-total").textContent = total;
    document.getElementById("stat-aggressive").textContent = aggressive;
    document.getElementById("stat-wache").textContent = wache;
    document.getElementById("stat-passive").textContent = passive;
    document.getElementById("stat-neutral").textContent = neutral;
    document.getElementById("stat-moving").textContent = moving;

    document.getElementById("badge-total").textContent = total;
    Object.keys(catCounts).forEach(function(key) {
      var badge = document.getElementById("badge-" + key);
      if (badge) badge.textContent = catCounts[key];
    });
  }

  function renderOverview() {
    var container = document.getElementById("category-overview");
    container.innerHTML = "";
    var catCounts = {};
    var catNpcs = {};
    Object.keys(categoryMap).forEach(function(key) {
      catCounts[key] = 0;
      catNpcs[key] = [];
    });
    npcList.forEach(function(npc) {
      var cat = getNpcCategory(npc);
      if (catCounts[cat] !== undefined) {
        catCounts[cat]++;
        catNpcs[cat].push(npc.name);
      }
    });
    Object.keys(categoryMap).forEach(function(key, idx) {
      var info = categoryMap[key];
      var card = document.createElement("div");
      card.className = "cat-card";
      card.style.animationDelay = (idx * 0.08) + "s";
      var npcsHtml = catNpcs[key].slice(0, 8).map(function(n) {
        return '<span class="cat-npc-tag">' + escapeHtml(n) + '</span>';
      }).join("");
      if (catNpcs[key].length > 8) npcsHtml += '<span class="cat-npc-tag">+' + (catNpcs[key].length - 8) + '</span>';
      card.innerHTML =
        '<div class="cat-card-header">' +
          '<div class="cat-card-icon ' + info.color + '"><i class="fa-solid ' + info.icon + '"></i></div>' +
          '<span class="cat-card-title">' + info.label + '</span>' +
          '<span class="cat-card-count">' + catCounts[key] + ' NPCs</span>' +
        '</div>' +
        '<div class="cat-card-npcs">' + (npcsHtml || '<span class="cat-npc-tag">Keine NPCs</span>') + '</div>';
      card.addEventListener("click", function() { switchPanel("npc-list", key); });
      container.appendChild(card);
    });
  }

  /* ===== NPC Cards Rendering ===== */
  function getFilteredNpcs() {
    var filtered = npcList;
    if (activeCategory) {
      filtered = filtered.filter(function(npc) { return getNpcCategory(npc) === activeCategory; });
    }
    if (searchQuery) {
      var q = searchQuery.toLowerCase();
      filtered = filtered.filter(function(npc) {
        return (npc.name && npc.name.toLowerCase().indexOf(q) !== -1) ||
               (npc.model && npc.model.toLowerCase().indexOf(q) !== -1) ||
               (npc.behavior && npc.behavior.toLowerCase().indexOf(q) !== -1);
      });
    }
    return filtered;
  }

  function renderFilterPills() {
    catFilterPills.innerHTML = "";
    var allPill = document.createElement("button");
    allPill.className = "filter-pill" + (!activeCategory ? " active" : "");
    allPill.textContent = "Alle";
    allPill.addEventListener("click", function() {
      activeCategory = null;
      topbarTitle.textContent = "Alle NPCs";
      renderNpcCards();
      sidebarNav.querySelectorAll(".nav-item").forEach(function(btn) {
        var p = btn.getAttribute("data-panel");
        var c = btn.getAttribute("data-category");
        btn.classList.toggle("active", p === "npc-list" && !c);
      });
    });
    catFilterPills.appendChild(allPill);
    Object.keys(categoryMap).forEach(function(key) {
      var pill = document.createElement("button");
      pill.className = "filter-pill" + (activeCategory === key ? " active" : "");
      pill.innerHTML = '<i class="fa-solid ' + categoryMap[key].icon + '"></i> ' + categoryMap[key].label;
      pill.addEventListener("click", function() {
        activeCategory = key;
        topbarTitle.textContent = categoryMap[key].label;
        renderNpcCards();
        sidebarNav.querySelectorAll(".nav-item").forEach(function(btn) {
          var p = btn.getAttribute("data-panel");
          var c = btn.getAttribute("data-category");
          btn.classList.toggle("active", p === "npc-list" && c === key);
        });
      });
      catFilterPills.appendChild(pill);
    });
  }

  function renderNpcCards() {
    renderFilterPills();
    var filtered = getFilteredNpcs();
    npcCardsGrid.innerHTML = "";
    emptyState.style.display = filtered.length === 0 ? "block" : "none";

    filtered.forEach(function(npc, idx) {
      var cat = getNpcCategory(npc);
      var catInfo = categoryMap[cat] || categoryMap.civilian;
      var bIcon = behaviorIcons[npc.behavior] || "fa-question";
      var wLabel = weaponLabels[npc.weapon] || (npc.weapon ? escapeHtml(npc.weapon) : "Keine");

      var card = document.createElement("div");
      card.className = "npc-card";
      card.style.animationDelay = (idx * 0.05) + "s";
      card.innerHTML =
        '<div class="npc-card-top">' +
          '<div class="npc-card-avatar behavior-' + escapeHtml(npc.behavior) + '"><i class="fa-solid ' + bIcon + '"></i></div>' +
          '<div>' +
            '<div class="npc-card-name">' + escapeHtml(npc.name) + '</div>' +
            '<div class="npc-card-model">' + escapeHtml(npc.model) + '</div>' +
          '</div>' +
          '<span class="npc-card-badge behavior-' + escapeHtml(npc.behavior) + '">' + escapeHtml(npc.behavior) + '</span>' +
        '</div>' +
        '<div class="npc-card-details">' +
          '<div class="npc-detail"><i class="fa-solid fa-gun"></i><span class="npc-detail-value">' + wLabel + '</span></div>' +
          '<div class="npc-detail"><i class="fa-solid fa-circle-dot"></i><span class="npc-detail-value">' + npc.radius + 'm</span></div>' +
          '<div class="npc-detail"><i class="fa-solid fa-compass"></i><span class="npc-detail-value">' + (typeof npc.heading !== "undefined" ? Number(npc.heading).toFixed(1) + '°' : '-') + '</span></div>' +
          '<div class="npc-detail"><i class="fa-solid fa-person-running"></i><span class="npc-detail-value">' + (isMoving(npc) ? "Ja" : "Nein") + '</span></div>' +
          '<div class="npc-detail"><i class="fa-solid fa-location-dot"></i><span class="npc-detail-value">' + (typeof npc.x !== "undefined" ? Number(npc.x).toFixed(1) + ', ' + Number(npc.y).toFixed(1) + ', ' + Number(npc.z).toFixed(1) : '-') + '</span></div>' +
          '<div class="npc-detail"><i class="fa-solid fa-tag"></i><span class="npc-detail-value">' + catInfo.label + '</span></div>' +
        '</div>' +
        (npc.ignoreGroups || npc.ignoreJobs ?
          '<div class="npc-card-details" style="margin-bottom:8px">' +
            (npc.ignoreGroups ? '<div class="npc-detail"><i class="fa-solid fa-users-slash"></i><span class="npc-detail-value">' + escapeHtml(npc.ignoreGroups) + '</span></div>' : '') +
            (npc.ignoreJobs ? '<div class="npc-detail"><i class="fa-solid fa-briefcase"></i><span class="npc-detail-value">' + escapeHtml(npc.ignoreJobs) + '</span></div>' : '') +
          '</div>' : '') +
        '<div class="npc-card-actions">' +
          '<button class="npc-action-btn btn-edit" data-id="' + npc.id + '"><i class="fa-solid fa-pen"></i> Bearbeiten</button>' +
          '<button class="npc-action-btn btn-delete" data-id="' + npc.id + '"><i class="fa-solid fa-trash"></i> Löschen</button>' +
          '<button class="npc-action-btn btn-teleport" data-id="' + npc.id + '"><i class="fa-solid fa-location-arrow"></i> Teleport</button>' +
        '</div>';

      npcCardsGrid.appendChild(card);
    });

    /* Event delegation for card actions */
    npcCardsGrid.querySelectorAll(".btn-edit").forEach(function(btn) {
      btn.addEventListener("click", function() { window.editNpc(Number(this.getAttribute("data-id"))); });
    });
    npcCardsGrid.querySelectorAll(".btn-delete").forEach(function(btn) {
      btn.addEventListener("click", function() { window.deleteNpc(Number(this.getAttribute("data-id"))); });
    });
    npcCardsGrid.querySelectorAll(".btn-teleport").forEach(function(btn) {
      btn.addEventListener("click", function() { window.teleportToNpc(Number(this.getAttribute("data-id"))); });
    });
  }

  /* Search */
  searchInput.addEventListener("input", function() {
    searchQuery = this.value;
    renderNpcCards();
  });

  /* ===== Form ===== */
  function fillWeaponSelect() {
    npcWeapon.innerHTML = "";
    weaponList.forEach(function(w) {
      var opt = document.createElement("option");
      opt.value = w.value;
      opt.textContent = w.label;
      npcWeapon.appendChild(opt);
    });
  }
  function fillBehaviorSelect() {
    npcBehavior.innerHTML = "";
    behaviorList.forEach(function(b) {
      var opt = document.createElement("option");
      opt.value = b.value;
      opt.textContent = b.label;
      npcBehavior.appendChild(opt);
    });
  }
  function fillNpcTypeSelect() {
    npcTypeSelect.innerHTML = "";
    npcTypes.forEach(function(npc, idx) {
      var opt = document.createElement("option");
      opt.value = idx;
      opt.textContent = npc.name + " (" + categoryMap[npc.category].label + ")";
      npcTypeSelect.appendChild(opt);
    });
  }

  function resetForm() {
    editNPC = null;
    if (npcTypes.length) {
      npcTypeSelect.value = 0;
      var npc = npcTypes[0];
      npcModel.value = npc.model;
      npcWeapon.value = npc.weapon || "";
      npcBehavior.value = npc.behavior;
      npcRadius.value = npc.radius;
      npcHeading.value = "0";
      npcMovement.checked = false;
      npcIgnoreGroups.value = "";
      npcIgnoreJobs.value = "";
    }
    updateFormMode();
  }

  function updateFormMode() {
    if (editNPC) {
      formHeader.innerHTML = '<i class="fa-solid fa-pen-to-square"></i><span>NPC bearbeiten: ' + escapeHtml(editNPC.name) + '</span>';
      npcCreateBtn.style.display = "none";
      npcSaveBtn.style.display = "flex";
      npcCancelBtn.style.display = "flex";
    } else {
      formHeader.innerHTML = '<i class="fa-solid fa-user-plus"></i><span>Neuen NPC erstellen</span>';
      npcCreateBtn.style.display = "flex";
      npcSaveBtn.style.display = "none";
      npcCancelBtn.style.display = "none";
    }
  }

  npcTypeSelect.addEventListener("change", function() {
    var npc = npcTypes[this.value];
    npcModel.value = npc.model;
    npcWeapon.value = npc.weapon || "";
    npcBehavior.value = npc.behavior;
    npcRadius.value = npc.radius;
    npcMovement.checked = false;
    npcIgnoreGroups.value = "";
    npcIgnoreJobs.value = "";
  });

  /* ===== CRUD Actions ===== */
  window.deleteNpc = function(id) {
    fetch('https://' + resourceName + '/deleteNPC', {
      method: 'POST',
      body: JSON.stringify({ id: id })
    })
    .then(function() {
      showToast("NPC erfolgreich gelöscht", "success");
      fetch('https://' + resourceName + '/getNPCList', { method: 'POST' });
    })
    .catch(function(err) {
      showToast("Fehler beim Löschen des NPCs", "error");
      console.error(err);
    });
  };

  window.editNpc = function(id) {
    editNPC = npcList.find(function(n) { return n.id === id; });
    if (editNPC) {
      var typeIdx = npcTypes.findIndex(function(npc) { return npc.model === editNPC.model; });
      npcTypeSelect.value = typeIdx !== -1 ? typeIdx : 0;
      npcModel.value = (editNPC.model || "").trim();
      npcWeapon.value = editNPC.weapon || "";
      npcBehavior.value = editNPC.behavior || "Passiv";
      npcRadius.value = editNPC.radius;
      npcHeading.value = typeof editNPC.heading !== "undefined" ? editNPC.heading : 0.0;
      npcMovement.checked = isMoving(editNPC);
      npcIgnoreGroups.value = editNPC.ignoreGroups || "";
      npcIgnoreJobs.value = editNPC.ignoreJobs || "";
      switchPanel("npc-create");
      dashboardUI.style.display = "flex";
      setNuiFocus(true);
      updateFormMode();
      showToast("NPC zum Bearbeiten geladen: " + escapeHtml(editNPC.name), "info");
    }
  };

  window.teleportToNpc = function(id) {
    fetch('https://' + resourceName + '/teleportToNPC', {
      method: 'POST',
      body: JSON.stringify({ id: id })
    })
    .then(function() {
      showToast("Teleport wird ausgeführt...", "info");
    })
    .catch(function(err) {
      showToast("Fehler beim Teleport", "error");
      console.error(err);
    });
  };

  /* Create NPC */
  npcCreateBtn.addEventListener("click", function(e) {
    e.preventDefault();
    if (editNPC) return;
    var typeIdx = npcTypeSelect.value;
    var modelTrimmed = (npcModel.value || "").trim();
    createPending = {
      name: npcTypes[typeIdx].name,
      model: modelTrimmed,
      weapon: npcWeapon.value,
      behavior: npcBehavior.value,
      radius: Number(npcRadius.value),
      movement: npcMovement.checked ? 1 : 0,
      ignoreGroups: npcIgnoreGroups.value,
      ignoreJobs: npcIgnoreJobs.value
    };
    dashboardUI.style.display = "none";
    mousePickOverlay.style.display = "block";
    setNuiFocus(false);
    fetch('https://' + resourceName + '/start_coord_pick', { method: 'POST' });
  });

  /* Save NPC (edit) */
  npcSaveBtn.addEventListener("click", function(e) {
    e.preventDefault();
    if (!editNPC) return;
    var typeIdx = npcTypeSelect.value;
    var modelTrimmed = (npcModel.value || "").trim();
    var updatedNPC = {
      id: editNPC.id,
      name: npcTypes[typeIdx].name,
      model: modelTrimmed,
      weapon: npcWeapon.value,
      behavior: npcBehavior.value,
      radius: Number(npcRadius.value),
      heading: Number(npcHeading.value),
      movement: npcMovement.checked ? 1 : 0,
      ignoreGroups: npcIgnoreGroups.value,
      ignoreJobs: npcIgnoreJobs.value,
      x: editNPC.x,
      y: editNPC.y,
      z: editNPC.z
    };
    fetch('https://' + resourceName + '/updateNPC', {
      method: 'POST',
      body: JSON.stringify(updatedNPC)
    })
    .then(function() {
      showToast("NPC erfolgreich aktualisiert", "success");
      editNPC = null;
      resetForm();
      switchPanel("npc-list");
      fetch('https://' + resourceName + '/getNPCList', { method: 'POST' });
    })
    .catch(function(err) {
      showToast("Fehler beim Aktualisieren", "error");
      console.error(err);
    });
  });

  /* Cancel edit */
  npcCancelBtn.addEventListener("click", function(e) {
    e.preventDefault();
    editNPC = null;
    resetForm();
    switchPanel("npc-list");
  });

  /* Keyboard: Enter for coord pick */
  window.addEventListener('keydown', function(e) {
    if (mousePickOverlay.style.display === 'block' && e.key === "Enter" && createPending) {
      createPending.x = createPending.x !== undefined ? Number(createPending.x) : 222.00;
      createPending.y = createPending.y !== undefined ? Number(createPending.y) : 111.00;
      createPending.z = createPending.z !== undefined ? Number(createPending.z) : 33.00;
      createPending.heading = createPending.heading !== undefined ? Number(createPending.heading) : 180.00;
      createPending.movement = createPending.movement ? 1 : 0;
      fetch('https://' + resourceName + '/addNPC', {
        method: 'POST',
        body: JSON.stringify(createPending)
      })
      .then(function() {
        mousePickOverlay.style.display = "none";
        dashboardUI.style.display = "flex";
        createPending = null;
        showToast("NPC erfolgreich erstellt!", "success");
        resetForm();
        switchPanel("npc-list");
        fetch('https://' + resourceName + '/getNPCList', { method: 'POST' });
      })
      .catch(function(err) {
        showToast("Fehler beim Hinzufügen des NPCs", "error");
        console.error(err);
      });
    }
  });

  /* Overlay mousedown cancel */
  overlay.addEventListener('mousedown', function() {
    mousePickOverlay.style.display = 'none';
    dashboardUI.style.display = "flex";
  });

  /* ===== NUI Messages ===== */
  window.addEventListener('message', function(event) {
    if (event.data.type === "open") {
      dashboardUI.style.display = "flex";
      switchPanel("overview");
      updateStats();
    }
    if (event.data.type === "close") {
      dashboardUI.style.display = "none";
      setNuiFocus(false);
    }
    if (event.data.type === "refresh") {
      if (event.data.npcs) {
        npcList = event.data.npcs;
        updateStats();
        if (activePanel === "npc-list") renderNpcCards();
        if (activePanel === "overview") renderOverview();
      }
    }
    if (event.data.type === "coord_selected") {
      if (!createPending) return;
      createPending.x = Number(event.data.coords.x);
      createPending.y = Number(event.data.coords.y);
      createPending.z = Number(event.data.coords.z);
      createPending.heading = Number(event.data.heading);
      createPending.movement = createPending.movement ? 1 : 0;
      fetch('https://' + resourceName + '/addNPC', {
        method: 'POST',
        body: JSON.stringify(createPending)
      })
      .then(function() {
        mousePickOverlay.style.display = "none";
        dashboardUI.style.display = "flex";
        createPending = null;
        showToast("NPC erfolgreich platziert!", "success");
        resetForm();
        switchPanel("npc-list");
        fetch('https://' + resourceName + '/getNPCList', { method: 'POST' });
      })
      .catch(function(err) {
        showToast("Fehler beim Hinzufügen des NPCs", "error");
        console.error(err);
      });
    }
  });

  /* Close dashboard - release focus immediately, then notify Lua */
  var isClosing = false;
  function closeDashboard() {
    if (isClosing) return;
    isClosing = true;
    dashboardUI.style.display = "none";
    setNuiFocus(false);
    fetch('https://' + resourceName + '/close', { method: 'POST' }).finally(function() {
      isClosing = false;
    });
  }

  /* Close button */
  closeBtn.addEventListener("click", function() {
    closeDashboard();
  });

  /* ESC key to close dashboard */
  window.addEventListener('keydown', function(e) {
    if (e.key === "Escape" && dashboardUI.style.display === "flex") {
      closeDashboard();
    }
  });

  /* ===== Init ===== */
  fillNpcTypeSelect();
  fillWeaponSelect();
  fillBehaviorSelect();
  resetForm();
  switchPanel("overview");
  updateStats();
});