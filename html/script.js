console.log("NPC Dashboard JS geladen!");

// Status an Server: HTML erfolgreich geladen!
if (typeof GetParentResourceName === "function") {
  fetch(`https://${GetParentResourceName()}/htmlGeladen`, { method: 'POST' });
}

const npcTypes = [
  { name: "Polizist", model: "s_m_y_cop_01", weapon: "WEAPON_PISTOL", behavior: "Neutral", radius: 15 },
  { name: "Sheriff", model: "s_m_y_sheriff_01", weapon: "WEAPON_PISTOL", behavior: "Neutral", radius: 15 },
  { name: "Gangmitglied", model: "g_m_y_ballaeast_01", weapon: "WEAPON_MICROSMG", behavior: "Aggressiv", radius: 10 },
  { name: "Mafia", model: "g_m_m_chicold_01", weapon: "WEAPON_PISTOL", behavior: "Aggressiv", radius: 10 },
  { name: "Dealer", model: "g_m_y_mexgoon_01", weapon: "WEAPON_PISTOL", behavior: "Neutral", radius: 10 },
  { name: "Sicherheitskraft", model: "s_m_m_security_01", weapon: "WEAPON_PISTOL", behavior: "Neutral", radius: 15 },
  { name: "Türsteher", model: "s_m_m_bouncer_01", weapon: "WEAPON_BAT", behavior: "Neutral", radius: 10 },
  { name: "Koch mit Messer", model: "s_m_y_chef_01", weapon: "WEAPON_KNIFE", behavior: "Passiv", radius: 8 },
  { name: "Pilot mit Pistole", model: "s_m_m_pilot_01", weapon: "WEAPON_PISTOL", behavior: "Neutral", radius: 10 },
  { name: "Mechaniker mit Schraubenschlüssel", model: "s_m_m_autoshop_01", weapon: "WEAPON_WRENCH", behavior: "Neutral", radius: 8 },
  { name: "Geschäftsmann", model: "a_m_m_business_01", weapon: "", behavior: "Passiv", radius: 8 },
  { name: "VIP", model: "a_m_y_business_01", weapon: "", behavior: "Neutral", radius: 8 },
  { name: "Sanitäter", model: "s_m_m_paramedic_01", weapon: "", behavior: "Passiv", radius: 10 },
  { name: "Feuerwehrmann", model: "s_m_y_fireman_01", weapon: "", behavior: "Passiv", radius: 10 },
  { name: "Taxifahrer", model: "s_m_m_taxi_01", weapon: "", behavior: "Passiv", radius: 8 },
  { name: "Obdachloser", model: "a_m_m_tramp_01", weapon: "", behavior: "Passiv", radius: 8 },
  { name: "Jogger", model: "a_m_y_jogger_01", weapon: "", behavior: "Passiv", radius: 8 },
  { name: "Bauarbeiter", model: "s_m_y_construct_01", weapon: "", behavior: "Neutral", radius: 10 },
  { name: "Arzt", model: "s_m_m_doctor_01", weapon: "", behavior: "Passiv", radius: 10 },
  { name: "Landwirt", model: "a_m_m_farmer_01", weapon: "", behavior: "Passiv", radius: 10 },
  { name: "Army", model: "s_m_y_marine_03", weapon: "WEAPON_CARBINERIFLE", behavior: "Aggressiv", radius: 20 }
];
const weaponList = [
  { label: "Keine Waffe", value: "" },
  { label: "Pistole", value: "WEAPON_PISTOL" },
  { label: "Maschinenpistole", value: "WEAPON_MICROSMG" },
  { label: "Messer", value: "WEAPON_KNIFE" },
  { label: "Schläger", value: "WEAPON_BAT" },
  { label: "Schraubenschlüssel", value: "WEAPON_WRENCH" }
];

const behaviorList = [
  { label: "Passiv", value: "Passiv" },
  { label: "Neutral", value: "Neutral" },
  { label: "Aggressiv", value: "Aggressiv" }
];

let npcList = [];
let editNPC = null;
let createPending = null;
let openTab = 0;
let focusState = true;

document.addEventListener("DOMContentLoaded", function() {
  const dashboardUI = document.getElementById("npc-dashboard-ui");
  const tabBar = document.getElementById("tab-bar");
  const npcListPanel = document.getElementById("npc-list-panel");
  const npcCreatePanel = document.getElementById("npc-create-panel");
  const npcTableBody = document.getElementById("npc-list");
  const npcTypeSelect = document.getElementById("npc-type-select");
  const npcModel = document.getElementById("npc-model");
  const npcWeapon = document.getElementById("npc-weapon");
  const npcBehavior = document.getElementById("npc-behavior");
  const npcRadius = document.getElementById("npc-radius");
  const npcHeading = document.getElementById("npc-heading");
  const npcCreateBtn = document.getElementById("npc-create-btn");
  const npcSaveBtn = document.getElementById("npc-save-btn");
  const closeBtn = document.getElementById("close-btn");
  const npcMovement = document.getElementById("npc-movement");
  const npcIgnoreGroups = document.getElementById("npc-ignore-groups");
  const npcIgnoreJobs = document.getElementById("npc-ignore-jobs");
  const mousePickOverlay = document.getElementById("mouse-pick-overlay");
  const overlay = document.getElementById("overlay");

  const tabs = [
    { name: "NPC-Liste", icon: "fa-users", panel: npcListPanel },
    { name: "NPC erstellen", icon: "fa-user-plus", panel: npcCreatePanel }
  ];

  function setNuiFocus(enable) {
    focusState = !!enable;
    if (typeof window.invokeNative === "function") {
      window.invokeNative("setNuiFocus", enable, enable);
    }
  }

  function renderTabs() {
    tabBar.innerHTML = '';
    tabs.forEach((tab, idx) => {
      const btn = document.createElement('button');
      btn.className = 'tab-btn' + (openTab === idx ? ' active' : '');
      btn.innerHTML = `<i class="fa-solid ${tab.icon}"></i><span>${tab.name}</span>`;
      btn.onclick = () => {
        editNPC = null;
        openTab = idx;
        showPanel();
        renderTabs();
        updatePanelMode();
      };
      tabBar.appendChild(btn);
    });
    showPanel();
    updatePanelMode();
  }

  function showPanel() {
    tabs.forEach((tab, idx) => {
      tab.panel.style.display = (idx === openTab) ? "block" : "none";
    });
    if (editNPC) openTab = 1;
    updatePanelMode();
  }

  function updatePanelMode() {
    if (openTab === 1 && editNPC) {
      npcCreateBtn.style.display = "none";
      npcSaveBtn.style.display = "inline-block";
    } else if (openTab === 1) {
      npcCreateBtn.style.display = "inline-block";
      npcSaveBtn.style.display = "none";
    }
  }

  function fillWeaponSelect() {
    npcWeapon.innerHTML = "";
    weaponList.forEach(w => {
      const opt = document.createElement("option");
      opt.value = w.value;
      opt.textContent = w.label;
      npcWeapon.appendChild(opt);
    });
  }
  function fillBehaviorSelect() {
    npcBehavior.innerHTML = "";
    behaviorList.forEach(b => {
      const opt = document.createElement("option");
      opt.value = b.value;
      opt.textContent = b.label;
      npcBehavior.appendChild(opt);
    });
  }
  function fillNpcTypeSelect() {
    npcTypeSelect.innerHTML = "";
    npcTypes.forEach((npc, idx) => {
      const opt = document.createElement("option");
      opt.value = idx;
      opt.textContent = npc.name;
      npcTypeSelect.appendChild(opt);
    });
  }

  function renderNpcTable() {
    npcTableBody.innerHTML = "";
    npcList.forEach((npc) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${npc.name}</td>
        <td>${npc.model}</td>
        <td>${npc.weapon ? npc.weapon : ""}</td>
        <td>${npc.behavior}</td>
        <td>${npc.radius}</td>
        <td>${typeof npc.x !== "undefined" ? Number(npc.x).toFixed(2) : ""}</td>
        <td>${typeof npc.y !== "undefined" ? Number(npc.y).toFixed(2) : ""}</td>
        <td>${typeof npc.z !== "undefined" ? Number(npc.z).toFixed(2) : ""}</td>
        <td>${typeof npc.heading !== "undefined" ? Number(npc.heading).toFixed(1) + "°" : "-"}</td>
        <td>${npc.movement ? "Ja" : "Nein"}</td>
        <td>${npc.ignoreGroups || ""}</td>
        <td>${npc.ignoreJobs || ""}</td>
        <td>
          <button class="npc-btn" onclick="window.editNpc(${npc.id})">Bearbeiten</button>
          <button class="npc-btn" onclick="window.deleteNpc(${npc.id})">Löschen</button>
          <button class="npc-btn" onclick="window.teleportToNpc(${npc.id})">Teleport</button>
        </td>
      `;
      npcTableBody.appendChild(tr);
    });
  }

  window.deleteNpc = function(id) {
    fetch('https://npc_dashboard/deleteNPC', {
      method: 'POST',
      body: JSON.stringify({ id })
    })
    .then(() => {
      fetch('https://npc_dashboard/getNPCList', { method: 'POST' });
    })
    .catch(err => {
      alert("Fehler beim Löschen des NPCs.");
      console.error(err);
    });
  }

  window.editNpc = function(id) {
    editNPC = npcList.find(n => n.id === id);
    if (editNPC) {
      const typeIdx = npcTypes.findIndex(npc => npc.model === editNPC.model);
      npcTypeSelect.value = typeIdx !== -1 ? typeIdx : 0;
      npcModel.value = (editNPC.model || "").trim();
      npcWeapon.value = editNPC.weapon || "";
      npcBehavior.value = editNPC.behavior || "Passiv";
      npcRadius.value = editNPC.radius;
      npcHeading.value = typeof editNPC.heading !== "undefined" ? editNPC.heading : 0.0;
      npcMovement.checked = !!editNPC.movement;
      npcIgnoreGroups.value = editNPC.ignoreGroups || "";
      npcIgnoreJobs.value = editNPC.ignoreJobs || "";
      openTab = 1;
      showPanel();
      renderTabs();
      dashboardUI.style.display = "flex";
      setNuiFocus(true);
      updatePanelMode();
    }
  }

  window.teleportToNpc = function(id) {
    fetch('https://npc_dashboard/teleportToNPC', {
      method: 'POST',
      body: JSON.stringify({ id })
    })
    .catch(err => {
      alert("Fehler beim Teleport.");
      console.error(err);
    });
  }

  npcTypeSelect.addEventListener("change", function() {
    const npc = npcTypes[this.value];
    npcModel.value = npc.model;
    npcWeapon.value = npc.weapon || "";
    npcBehavior.value = npc.behavior;
    npcRadius.value = npc.radius;
    npcModel.disabled = false;
    npcWeapon.disabled = false;
    npcBehavior.disabled = false;
    npcRadius.disabled = false;
    npcMovement.checked = false;
    npcIgnoreGroups.value = "";
    npcIgnoreJobs.value = "";
  });

  npcCreateBtn.addEventListener("click", function(e) {
    e.preventDefault();
    if (editNPC) return;
    const typeIdx = npcTypeSelect.value;
    const modelTrimmed = (npcModel.value || "").trim();
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
    fetch('https://npc_dashboard/start_coord_pick', { method: 'POST' });
  });

  if (npcSaveBtn) {
    npcSaveBtn.addEventListener("click", function(e) {
      e.preventDefault();
      if (!editNPC) return;
      const typeIdx = npcTypeSelect.value;
      const modelTrimmed = (npcModel.value || "").trim();
      const updatedNPC = {
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
      fetch('https://npc_dashboard/updateNPC', {
        method: 'POST',
        body: JSON.stringify(updatedNPC)
      })
      .then(() => {
        editNPC = null;
        openTab = 0;
        showPanel();
        renderTabs();
        fetch('https://npc_dashboard/getNPCList', { method: 'POST' });
      })
      .catch(err => {
        alert("Fehler beim Aktualisieren des NPCs.");
        console.error(err);
      });
    });
  }

  window.addEventListener('keydown', function(e) {
    if (mousePickOverlay.style.display === 'block' && e.key === "Enter") {
      createPending.x = createPending.x !== undefined ? Number(createPending.x) : 222.00;
      createPending.y = createPending.y !== undefined ? Number(createPending.y) : 111.00;
      createPending.z = createPending.z !== undefined ? Number(createPending.z) : 33.00;
      createPending.heading = createPending.heading !== undefined ? Number(createPending.heading) : 180.00;
      createPending.movement = createPending.movement ? 1 : 0;
      fetch('https://npc_dashboard/addNPC', {
        method: 'POST',
        body: JSON.stringify(createPending)
      })
      .then(() => {
        mousePickOverlay.style.display = "none";
        dashboardUI.style.display = "flex";
        setNuiFocus(true);
        createPending = null;
        openTab = 0;
        showPanel();
        renderTabs();
        fetch('https://npc_dashboard/getNPCList', { method: 'POST' });
      })
      .catch(err => {
        alert("Fehler beim Hinzufügen des NPCs.");
        console.error(err);
      });
    }
  });

  overlay.addEventListener('mousedown', function(e){
    mousePickOverlay.style.display = 'none';
    setNuiFocus(true);
    dashboardUI.style.display = "flex";
  });

  window.addEventListener('message', function(event) {
    if (event.data.type === "open") {
      dashboardUI.style.display = "flex";
      setNuiFocus(true);
      renderNpcTable();
      updatePanelMode();
    }
    if (event.data.type === "close") {
      dashboardUI.style.display = "none";
      setNuiFocus(false);
    }
    if (event.data.type === "refresh") {
      if (event.data.npcs) {
        npcList = event.data.npcs;
        renderNpcTable();
        updatePanelMode();
      }
    }
    if (event.data.type === "coord_selected") {
      createPending.x = Number(event.data.coords.x);
      createPending.y = Number(event.data.coords.y);
      createPending.z = Number(event.data.coords.z);
      createPending.heading = Number(event.data.heading);
      createPending.movement = createPending.movement ? 1 : 0;
      fetch('https://npc_dashboard/addNPC', {
        method: 'POST',
        body: JSON.stringify(createPending)
      })
      .then(() => {
        mousePickOverlay.style.display = "none";
        dashboardUI.style.display = "flex";
        setNuiFocus(true);
        createPending = null;
        openTab = 0;
        showPanel();
        renderTabs();
        fetch('https://npc_dashboard/getNPCList', { method: 'POST' });
      })
      .catch(err => {
        alert("Fehler beim Hinzufügen des NPCs.");
        console.error(err);
      });
    }
  });

  closeBtn.addEventListener("click", function() {
    dashboardUI.style.display = "none";
    setNuiFocus(false);
    fetch('https://npc_dashboard/close', { method: 'POST' });
  });

  fillNpcTypeSelect();
  fillWeaponSelect();
  fillBehaviorSelect();
  if(npcTypes.length) {
    const npc = npcTypes[0];
    npcModel.value = npc.model;
    npcWeapon.value = npc.weapon || "";
    npcBehavior.value = npc.behavior;
    npcRadius.value = npc.radius;
    npcMovement.checked = false;
    npcIgnoreGroups.value = "";
    npcIgnoreJobs.value = "";
  }
  renderTabs();
  renderNpcTable();
  updatePanelMode();
});