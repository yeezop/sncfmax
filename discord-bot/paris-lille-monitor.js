const { Client, GatewayIntentBits, EmbedBuilder } = require('discord.js');
const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');

// Configuration
const DISCORD_TOKEN = process.env.DISCORD_TOKEN;
const CHANNEL_ID = process.env.DISCORD_CHANNEL_ID;
const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3000';
const API_KEY = process.env.API_KEY || '';

// Route Paris -> Lille
const ORIGIN = 'FRPNO';           // Paris Nord
const ORIGIN_NAME = 'Paris Nord';
const DESTINATION = 'FRADJ';      // Lille Flandres (plus de trains que Lille Europe)
const DESTINATION_NAME = 'Lille Flandres';

// Date a surveiller - Vendredi 16 janvier 2026
const TARGET_DATE = new Date('2026-01-16');

// Filtre horaire - uniquement apres 14h
const MIN_HOUR = 14;

// Intervalle de scan (15 minutes)
const SCAN_INTERVAL = 15 * 60 * 1000;

// Stats de requetes
let totalRequests = 0;
let totalBytesReceived = 0;
let sessionStartTime = Date.now();

// Fichier de persistance pour les trains notifies
const DATA_FILE = process.env.DATA_FILE || '/app/data/notified-trains.json';

// Charger les trains deja notifies depuis le fichier
function loadNotifiedTrains() {
  try {
    if (fs.existsSync(DATA_FILE)) {
      const data = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
      log(`Charge ${data.length} trains deja notifies depuis ${DATA_FILE}`);
      return new Set(data);
    }
  } catch (e) {
    log(`Erreur lecture fichier: ${e.message}`);
  }
  return new Set();
}

// Sauvegarder les trains notifies dans le fichier
function saveNotifiedTrains() {
  try {
    const dir = path.dirname(DATA_FILE);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(DATA_FILE, JSON.stringify([...notifiedTrains], null, 2));
  } catch (e) {
    log(`Erreur sauvegarde fichier: ${e.message}`);
  }
}

// Trains deja notifies (persistes sur disque)
const notifiedTrains = loadNotifiedTrains();

const client = new Client({
  intents: [GatewayIntentBits.Guilds],
});

function log(message) {
  console.log(`[${new Date().toISOString()}] ${message}`);
}

function formatDate(date) {
  const days = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
  const months = ['janvier', 'fevrier', 'mars', 'avril', 'mai', 'juin',
                  'juillet', 'aout', 'septembre', 'octobre', 'novembre', 'decembre'];
  return `${days[date.getDay()]} ${date.getDate()} ${months[date.getMonth()]} ${date.getFullYear()}`;
}

function formatTime(isoString) {
  const date = new Date(isoString);
  return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function formatDuration(ms) {
  const hours = Math.floor(ms / (1000 * 60 * 60));
  const minutes = Math.floor((ms % (1000 * 60 * 60)) / (1000 * 60));
  if (hours > 0) return `${hours}h ${minutes}min`;
  return `${minutes}min`;
}

async function searchTrains(date) {
  const dateStr = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 1)).toISOString();
  const url = `${BACKEND_URL}/api/trains?origin=${ORIGIN}&destination=${DESTINATION}&date=${encodeURIComponent(dateStr)}&refresh=true`;

  const headers = {
    'Accept': 'application/json',
  };
  if (API_KEY) {
    headers['x-api-key'] = API_KEY;
  }

  try {
    const startTime = Date.now();
    const response = await fetch(url, {
      headers,
      timeout: 60000
    });

    const text = await response.text();
    const requestTime = Date.now() - startTime;
    const bytesReceived = Buffer.byteLength(text, 'utf8');

    // Update stats
    totalRequests++;
    totalBytesReceived += bytesReceived;

    log(`Request #${totalRequests}: ${formatBytes(bytesReceived)} in ${requestTime}ms`);

    const data = JSON.parse(text);

    if (data.errorCode) {
      log(`Pas de trains pour ${formatDate(date)}: ${data.message}`);
      return {
        date,
        proposals: [],
        ratio: 0,
        requestStats: { bytes: bytesReceived, time: requestTime }
      };
    }

    return {
      date,
      proposals: data.proposals || [],
      ratio: data.ratio || 0,
      cached: data._cached || false,
      requestStats: { bytes: bytesReceived, time: requestTime }
    };
  } catch (error) {
    log(`Erreur pour ${formatDate(date)}: ${error.message}`);
    totalRequests++;
    return {
      date,
      proposals: [],
      ratio: 0,
      error: error.message,
      requestStats: { bytes: 0, time: 0 }
    };
  }
}

function getTrainId(train, date) {
  const dateKey = date.toISOString().split('T')[0];
  return `${dateKey}-${train.num}`;
}

function isTrainAlreadyNotified(trainId) {
  return notifiedTrains.has(trainId);
}

function markTrainAsNotified(trainId) {
  notifiedTrains.add(trainId);
  saveNotifiedTrains(); // Persister immediatement
}

function filterTrainsAfter14h(proposals) {
  return proposals.filter(train => {
    const depTime = new Date(train.dep);
    return depTime.getHours() >= MIN_HOUR;
  });
}

async function sendNewTrainNotification(channel, train, date) {
  const trainId = getTrainId(train, date);

  if (isTrainAlreadyNotified(trainId)) {
    return false;
  }

  markTrainAsNotified(trainId);

  const depTime = new Date(train.dep);
  const arrTime = new Date(train.arr);
  const duration = Math.round((arrTime - depTime) / (1000 * 60));

  const embed = new EmbedBuilder()
    .setColor(0x00FF00)
    .setTitle('🚄 NOUVEAU - Place TGV Max disponible!')
    .setDescription(`**${ORIGIN_NAME}** → **${DESTINATION_NAME}**`)
    .addFields(
      { name: '📅 Date', value: formatDate(date), inline: true },
      { name: '🚂 Train', value: `${train.type || 'TGV'} ${train.num}`, inline: true },
      { name: '🎫 Places', value: `${train.count}`, inline: true },
      { name: '🕐 Depart', value: formatTime(train.dep), inline: true },
      { name: '🕐 Arrivee', value: formatTime(train.arr), inline: true },
      { name: '⏱️ Duree', value: `${duration} min`, inline: true },
    )
    .setTimestamp()
    .setFooter({ text: 'TGV Max Alert - Paris-Lille' });

  await channel.send({ content: '@here', embeds: [embed] });
  log(`NOTIFICATION: Train ${train.num} - ${formatTime(train.dep)} - ${train.count} places`);
  return true;
}

async function sendScanSummary(channel, result, newTrainsCount) {
  const trainsAfter14h = filterTrainsAfter14h(result.proposals);
  const totalSeats = trainsAfter14h.reduce((s, p) => s + p.count, 0);
  const availableTrains = trainsAfter14h.filter(t => t.count > 0);

  // Liste des horaires disponibles apres 14h
  let trainsListStr = '';
  if (availableTrains.length > 0) {
    trainsListStr = availableTrains
      .sort((a, b) => new Date(a.dep) - new Date(b.dep))
      .map(t => `• **${formatTime(t.dep)}** → ${formatTime(t.arr)} (${t.count} place${t.count > 1 ? 's' : ''})`)
      .join('\n');
  } else {
    trainsListStr = '_Aucun train disponible apres 14h_';
  }

  // Stats de la session
  const sessionDuration = Date.now() - sessionStartTime;
  const avgBytesPerRequest = totalRequests > 0 ? Math.round(totalBytesReceived / totalRequests) : 0;

  const embed = new EmbedBuilder()
    .setColor(newTrainsCount > 0 ? 0x00FF00 : (availableTrains.length > 0 ? 0x3498DB : 0x808080))
    .setTitle(`📊 Scan ${ORIGIN_NAME} → ${DESTINATION_NAME}`)
    .setDescription(`**${formatDate(result.date)}** - Trains apres 14h`)
    .addFields(
      { name: '🚄 Trains disponibles', value: `${availableTrains.length} trains, ${totalSeats} places`, inline: false },
      { name: '📋 Horaires (apres 14h)', value: trainsListStr.substring(0, 1024), inline: false },
      { name: '🆕 Nouveaux trains', value: `${newTrainsCount}`, inline: true },
      { name: '📝 Deja notifies', value: `${notifiedTrains.size}`, inline: true },
      { name: '📡 Cache', value: result.cached ? 'Oui' : 'Non', inline: true },
    )
    .addFields(
      { name: '\u200B', value: '**📈 Stats Proxy**', inline: false },
      { name: 'Requetes totales', value: `${totalRequests}`, inline: true },
      { name: 'Donnees recues', value: formatBytes(totalBytesReceived), inline: true },
      { name: 'Moy/requete', value: formatBytes(avgBytesPerRequest), inline: true },
      { name: 'Derniere requete', value: formatBytes(result.requestStats?.bytes || 0), inline: true },
      { name: 'Session active', value: formatDuration(sessionDuration), inline: true },
    )
    .setTimestamp()
    .setFooter({ text: 'Prochain scan dans 15 minutes' });

  await channel.send({ embeds: [embed] });
}

async function runScan() {
  log('='.repeat(60));
  log(`Scan: ${ORIGIN_NAME} -> ${DESTINATION_NAME} pour ${formatDate(TARGET_DATE)}`);

  const channel = client.channels.cache.get(CHANNEL_ID);
  if (!channel) {
    log(`Erreur: Channel ${CHANNEL_ID} non trouve`);
    return;
  }

  // Rechercher les trains
  const result = await searchTrains(TARGET_DATE);

  if (result.error) {
    log(`Erreur lors du scan: ${result.error}`);

    // Envoyer un message d'erreur sur Discord
    const errorEmbed = new EmbedBuilder()
      .setColor(0xFF0000)
      .setTitle('⚠️ Erreur de scan')
      .setDescription(`Impossible de recuperer les trains`)
      .addFields(
        { name: 'Route', value: `${ORIGIN_NAME} → ${DESTINATION_NAME}`, inline: true },
        { name: 'Erreur', value: result.error.substring(0, 200), inline: false },
        { name: 'Requetes totales', value: `${totalRequests}`, inline: true },
        { name: 'Donnees proxy', value: formatBytes(totalBytesReceived), inline: true },
      )
      .setTimestamp()
      .setFooter({ text: 'Prochain scan dans 15 minutes' });

    await channel.send({ embeds: [errorEmbed] });
    return;
  }

  // Filtrer les trains apres 14h
  const trainsAfter14h = filterTrainsAfter14h(result.proposals);
  log(`Total: ${result.proposals.length} trains, dont ${trainsAfter14h.length} apres 14h`);

  let newTrainsCount = 0;

  // Notifier les nouveaux trains disponibles (apres 14h uniquement)
  for (const train of trainsAfter14h) {
    if (train.count > 0) {
      const wasNew = await sendNewTrainNotification(channel, train, TARGET_DATE);
      if (wasNew) newTrainsCount++;
    }
  }

  // Envoyer le resume
  await sendScanSummary(channel, result, newTrainsCount);

  log(`Scan termine - ${newTrainsCount} nouveau(x) train(s)`);
  log(`Stats: ${totalRequests} requetes, ${formatBytes(totalBytesReceived)} recus`);
  log('='.repeat(60));
}

client.once('ready', async () => {
  log(`Bot connecte: ${client.user.tag}`);
  log(`Surveillance: ${ORIGIN_NAME} -> ${DESTINATION_NAME}`);
  log(`Date: ${formatDate(TARGET_DATE)}`);
  log(`Filtre: Trains apres ${MIN_HOUR}h`);
  log(`Intervalle: ${SCAN_INTERVAL / 1000 / 60} minutes`);
  log(`Backend: ${BACKEND_URL}`);

  // Premier scan immediat
  await runScan();

  // Scans reguliers toutes les 15 minutes
  setInterval(runScan, SCAN_INTERVAL);
});

// Gestion des erreurs
client.on('error', (error) => {
  log(`Erreur Discord: ${error.message}`);
});

process.on('unhandledRejection', (error) => {
  log(`Erreur non geree: ${error.message}`);
});

process.on('SIGINT', () => {
  log('Fermeture...');
  log(`Session finale: ${totalRequests} requetes, ${formatBytes(totalBytesReceived)}`);
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Fermeture...');
  log(`Session finale: ${totalRequests} requetes, ${formatBytes(totalBytesReceived)}`);
  process.exit(0);
});

// Demarrage
if (!DISCORD_TOKEN) {
  console.error('DISCORD_TOKEN non defini!');
  console.error('Usage: DISCORD_TOKEN=xxx DISCORD_CHANNEL_ID=yyy node paris-lille-monitor.js');
  process.exit(1);
}

if (!CHANNEL_ID) {
  console.error('DISCORD_CHANNEL_ID non defini!');
  console.error('Usage: DISCORD_TOKEN=xxx DISCORD_CHANNEL_ID=yyy node paris-lille-monitor.js');
  process.exit(1);
}

log('Demarrage du bot Paris-Lille...');
client.login(DISCORD_TOKEN);
