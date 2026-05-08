// State Variables
let scores = [0, 0, 0];
let activeValue = null;
let currentProfile = null;
let boardState = []; // 0: unrevealed, 1: question, 2: answer, 3: done
let gameProfiles = {};
let serverProfiles = {}; // Profiles loaded from server (read-only)

// Initialization
document.addEventListener("DOMContentLoaded", () => {
    loadProfilesFromStorage();
    loadServerProfiles();
    updateUI();
});

// Load bundled game profiles from the server
async function loadServerProfiles() {
    try {
        const resp = await fetch('games/manifest.json');
        if (!resp.ok) return;
        const files = await resp.json();
        for (const file of files) {
            try {
                const r = await fetch('games/' + file);
                if (!r.ok) continue;
                const data = await r.json();
                if (data.name && data.categories) {
                    serverProfiles[data.name] = data;
                    // Server profiles fill in without overwriting user uploads
                    if (!gameProfiles[data.name]) {
                        gameProfiles[data.name] = data;
                    }
                }
            } catch (_) { /* skip bad files */ }
        }
        populateSelect();
    } catch (_) { /* manifest not available, that's fine */ }
}

// Load profiles from local storage
function loadProfilesFromStorage() {
    const stored = localStorage.getItem("jeopardyProfiles");
    if (stored) {
        gameProfiles = JSON.parse(stored);
        populateSelect();
    }
}

function saveProfilesToStorage() {
    // Only save user-uploaded profiles, not server-bundled ones
    const userOnly = {};
    for (const name in gameProfiles) {
        if (!serverProfiles[name]) {
            userOnly[name] = gameProfiles[name];
        }
    }
    localStorage.setItem("jeopardyProfiles", JSON.stringify(userOnly));
}

function populateSelect() {
    const select = document.getElementById('profile-select');
    select.innerHTML = '<option value="">-- Select Game Profile --</option>';
    for (const name in gameProfiles) {
        const option = document.createElement('option');
        option.value = name;
        option.textContent = name;
        select.appendChild(option);
    }
}

// File Upload
function handleFileUpload(event) {
    const file = event.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = function(e) {
        try {
            const data = JSON.parse(e.target.result);
            if (!data.name || !data.categories) {
                alert("Invalid format. Needs 'name' and 'categories' array.");
                return;
            }
            gameProfiles[data.name] = data;
            saveProfilesToStorage();
            populateSelect();
            alert(`Profile "${data.name}" loaded successfully!`);
            document.getElementById('profile-select').value = data.name;
            loadSelectedProfile();
        } catch (err) {
            alert("Error parsing JSON file.");
        }
    };
    reader.readAsText(file);
    event.target.value = ''; // Reset
}

// Load Game Profile
function loadSelectedProfile() {
    const name = document.getElementById('profile-select').value;
    if (!name) return;

    currentProfile = gameProfiles[name];
    resetGame(false);
}

// Reset Game
function confirmReset() {
    if (confirm("Are you sure you want to reset the board and scores?")) {
        resetGame(true);
    }
}

function resetGame(resetScores) {
    if (resetScores) {
        scores = [0, 0, 0];
    }
    activeValue = null;
    
    if (!currentProfile) {
        document.getElementById('board').innerHTML = "";
        updateUI();
        return;
    }

    // Initialize board state based on actual data dimensions
    const numCols = currentProfile.categories.length;
    const numRows = Math.max(...currentProfile.categories.map(c => c.questions.length));
    boardState = Array(numCols * numRows).fill(0);
    renderBoard();
    updateUI();
}

// Rendering
function renderBoard() {
    const board = document.getElementById('board');
    board.innerHTML = "";

    const numCols = currentProfile.categories.length;
    const numRows = Math.max(...currentProfile.categories.map(c => c.questions.length));

    // Set grid dimensions dynamically
    board.style.gridTemplateColumns = `repeat(${numCols}, 1fr)`;
    board.style.gridTemplateRows = `min-content repeat(${numRows}, 1fr)`;

    // Header
    currentProfile.categories.forEach(cat => {
        const div = document.createElement('div');
        div.className = 'category';
        div.textContent = cat.title;
        board.appendChild(div);
    });

    // Grid (dynamic rows and cols)
    for (let r = 0; r < numRows; r++) {
        for (let c = 0; c < numCols; c++) {
            const index = r * numCols + c;
            const cat = currentProfile.categories[c];
            const qData = cat.questions[r] || { q: "Empty", a: "Empty", v: (r+1)*100 };
            
            const cell = document.createElement('div');
            cell.className = 'cell';
            cell.dataset.index = index;
            
            // Assign onclick handler
            cell.onclick = () => handleCellClick(index, qData, cell);
            
            applyCellState(cell, index, qData);
            board.appendChild(cell);
        }
    }
}

function applyCellState(cell, index, qData) {
    const state = boardState[index];
    cell.className = 'cell'; // reset
    if (state === 0) {
        cell.textContent = `$${qData.v}`;
    } else if (state === 1) {
        cell.classList.add('question');
        cell.textContent = qData.q;
    } else if (state === 2) {
        cell.classList.add('answer');
        cell.textContent = qData.a;
    } else if (state === 3) {
        cell.classList.add('done');
        cell.textContent = qData.a;
    }
}

function handleCellClick(index, qData, cell) {
    let state = boardState[index];
    if (state === 3) return; // Done

    state++;
    boardState[index] = state;
    
    // Set active value for scoring
    if (state === 1 || state === 2) {
        activeValue = qData.v;
    } else {
        activeValue = null;
    }
    
    applyCellState(cell, index, qData);
    updateUI();
}

// Scoring
function addScore(playerNum) {
    if (activeValue === null) {
        alert("No active question to award points for! Click a cell first.");
        return;
    }
    scores[playerNum - 1] += activeValue;
    activeValue = null; // Clear active value after awarding
    
    // Auto-advance any open cells to state 3 (done)
    for (let i = 0; i < boardState.length; i++) {
        if (boardState[i] === 1 || boardState[i] === 2) {
            boardState[i] = 3;
        }
    }
    renderBoard();
    updateUI();
}

function manualScore(playerNum, amount) {
    scores[playerNum - 1] += amount;
    updateUI();
}

// Download current game profile as JSON
function downloadProfile() {
    if (!currentProfile) {
        alert('No game profile loaded to download.');
        return;
    }
    const json = JSON.stringify(currentProfile, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = (currentProfile.name || 'game-profile').replace(/[^a-z0-9_-]/gi, '_') + '.json';
    a.click();
    URL.revokeObjectURL(url);
}

function updateUI() {
    document.getElementById('score-p1').textContent = `$${scores[0]}`;
    document.getElementById('score-p2').textContent = `$${scores[1]}`;
    document.getElementById('score-p3').textContent = `$${scores[2]}`;

    // Show/hide download link based on active profile
    const dlBtn = document.getElementById('btn-download');
    dlBtn.style.display = currentProfile ? 'inline-flex' : 'none';
    
    const activeDisplay = document.getElementById('active-value');
    if (activeValue !== null) {
        activeDisplay.textContent = `$${activeValue}`;
    } else {
        activeDisplay.textContent = 'None';
    }
}