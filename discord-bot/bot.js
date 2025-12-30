const { Client, GatewayIntentBits, EmbedBuilder } = require('discord.js');
const fetch = require('node-fetch');
const Database = require('better-sqlite3');

// Configuration
const DISCORD_TOKEN = process.env.DISCORD_TOKEN;
const CHANNEL_ID = process.env.DISCORD_CHANNEL_ID;
const BACKEND_URL = process.env.BACKEND_URL || 'http://sncfmax-backend:3000';

// Route a surveiller
const ORIGIN = 'FRLRH';           // La Rochelle Ville
const ORIGIN_NAME = 'La Rochelle Ville';
const DESTINATION = 'FRPST';      // Paris Est
const DESTINATION_NAME = 'Paris Est';

// Dates a surveiller (1, 2, 3 janvier 2026)
const DATES_TO_WATCH = [
  new Date('2026-01-01'), // Jeudi
  new Date('2026-01-02'), // Vendredi
  new Date('2026-01-03'), // Samedi
];

// Intervalle de scan (15 minutes)
const SCAN_INTERVAL = 15 * 60 * 1000;

// Database SQLite
const db = new Database('/app/data/notifications.db');

// Initialiser la base de donnees
db.exec(`
  CREATE TABLE IF NOT EXISTS notified_trains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    train_id TEXT UNIQUE NOT NULL,
    train_num TEXT NOT NULL,
    train_date TEXT NOT NULL,
    seats INTEGER NOT NULL,
    notified_at DATETIME DEFAULT CURRENT_TIMESTAMP
  )
`);

const insertTrain = db.prepare(`
  INSERT OR IGNORE INTO notified_trains (train_id, train_num, train_date, seats)
  VALUES (?, ?, ?, ?)
`);

const checkTrain = db.prepare(`
  SELECT * FROM notified_trains WHERE train_id = ?
`);

const getAllNotified = db.prepare(`
  SELECT * FROM notified_trains ORDER BY notified_at DESC
`);

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
  ],
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

async function searchTrains(date) {
  const dateStr = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 1)).toISOString();
  const url = `${BACKEND_URL}/api/trains?origin=${ORIGIN}&destination=${DESTINATION}&date=${encodeURIComponent(dateStr)}`;

  try {
    const response = await fetch(url, { timeout: 60000 });
    const data = await response.json();

    if (data.errorCode) {
      log(`Pas de trains pour ${formatDate(date)}: ${data.message}`);
      return { date, proposals: [], ratio: 0 };
    }

    return {
      date,
      proposals: data.proposals || [],
      ratio: data.ratio || 0,
    };
  } catch (error) {
    log(`Erreur pour ${formatDate(date)}: ${error.message}`);
    return { date, proposals: [], ratio: 0, error: error.message };
  }
}

function isTrainAlreadyNotified(trainId) {
  const result = checkTrain.get(trainId);
  return result !== undefined;
}

function markTrainAsNotified(trainId, trainNum, trainDate, seats) {
  try {
    insertTrain.run(trainId, trainNum, trainDate, seats);
    return true;
  } catch (error) {
    log(`Erreur DB: ${error.message}`);
    return false;
  }
}

async function sendNotification(channel, train, date) {
  const dateKey = date.toISOString().split('T')[0];
  const trainId = `${dateKey}-${train.num}`;

  // Verifier si deja notifie dans la BDD
  if (isTrainAlreadyNotified(trainId)) {
    log(`Train ${train.num} du ${dateKey} deja notifie, skip`);
    return false;
  }

  // Marquer comme notifie dans la BDD
  markTrainAsNotified(trainId, train.num, dateKey, train.count);

  const embed = new EmbedBuilder()
    .setColor(0x00FF00)
    .setTitle('🚄 NOUVEAU - Place TGV Max disponible!')
    .setDescription(`**${ORIGIN_NAME}** → **${DESTINATION_NAME}**`)
    .addFields(
      { name: '📅 Date', value: formatDate(date), inline: true },
      { name: '🚂 Train', value: `${train.type} ${train.num}`, inline: true },
      { name: '🎫 Places', value: `${train.count}`, inline: true },
      { name: '🕐 Depart', value: formatTime(train.dep), inline: true },
      { name: '🕐 Arrivee', value: formatTime(train.arr), inline: true },
      { name: '\u200B', value: '\u200B', inline: true },
    )
    .setTimestamp()
    .setFooter({ text: 'TGV Max Alert Bot' });

  await channel.send({ content: '@here', embeds: [embed] });
  log(`NOUVELLE notification: Train ${train.num} le ${formatDate(date)} - ${train.count} places`);
  return true;
}

async function sendSummary(channel, results, newTrainsCount) {
  const totalTrains = results.reduce((sum, r) => sum + r.proposals.length, 0);
  const totalSeats = results.reduce((sum, r) =>
    sum + r.proposals.reduce((s, p) => s + p.count, 0), 0);

  let description = '';
  for (const result of results) {
    const seats = result.proposals.reduce((s, p) => s + p.count, 0);
    const emoji = seats > 0 ? '✅' : '❌';
    description += `${emoji} **${formatDate(result.date)}**: ${result.proposals.length} trains, ${seats} places\n`;
  }

  // Nombre de trains deja notifies
  const notifiedCount = getAllNotified.all().length;

  const embed = new EmbedBuilder()
    .setColor(newTrainsCount > 0 ? 0x00FF00 : 0x808080)
    .setTitle(`📊 Scan ${ORIGIN_NAME} → ${DESTINATION_NAME}`)
    .setDescription(description)
    .addFields(
      { name: 'Total disponible', value: `${totalTrains} trains, ${totalSeats} places`, inline: false },
      { name: 'Nouveaux trains', value: `${newTrainsCount}`, inline: true },
      { name: 'Deja notifies', value: `${notifiedCount}`, inline: true },
    )
    .setTimestamp()
    .setFooter({ text: 'Prochain scan dans 15 minutes' });

  await channel.send({ embeds: [embed] });
}

async function runScan() {
  log('='.repeat(50));
  log('Demarrage du scan...');

  const channel = client.channels.cache.get(CHANNEL_ID);
  if (!channel) {
    log(`Erreur: Channel ${CHANNEL_ID} non trouve`);
    return;
  }

  const results = [];
  let newTrainsCount = 0;

  for (const date of DATES_TO_WATCH) {
    const result = await searchTrains(date);
    results.push(result);

    // Notifier uniquement les nouveaux trains
    for (const train of result.proposals) {
      if (train.count > 0) {
        const wasNew = await sendNotification(channel, train, date);
        if (wasNew) newTrainsCount++;
      }
    }

    // Petit delai entre les requetes
    await new Promise(resolve => setTimeout(resolve, 500));
  }

  // Envoyer un resume
  await sendSummary(channel, results, newTrainsCount);

  log(`Scan termine - ${newTrainsCount} nouveau(x) train(s)`);
  log('='.repeat(50));
}

client.once('ready', async () => {
  log(`Bot connecte: ${client.user.tag}`);
  log(`Surveillance: ${ORIGIN_NAME} -> ${DESTINATION_NAME}`);
  log(`Dates: ${DATES_TO_WATCH.map(d => formatDate(d)).join(', ')}`);
  log(`Intervalle: ${SCAN_INTERVAL / 1000 / 60} minutes`);
  log(`Trains deja notifies: ${getAllNotified.all().length}`);

  // Premier scan immediat
  await runScan();

  // Scans reguliers
  setInterval(runScan, SCAN_INTERVAL);
});

// Gestion des erreurs
client.on('error', (error) => {
  log(`Erreur Discord: ${error.message}`);
});

process.on('unhandledRejection', (error) => {
  log(`Erreur non geree: ${error.message}`);
});

// Fermer proprement la BDD
process.on('SIGINT', () => {
  log('Fermeture...');
  db.close();
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('Fermeture...');
  db.close();
  process.exit(0);
});

// Demarrage
if (!DISCORD_TOKEN) {
  console.error('DISCORD_TOKEN non defini!');
  process.exit(1);
}

if (!CHANNEL_ID) {
  console.error('DISCORD_CHANNEL_ID non defini!');
  process.exit(1);
}

client.login(DISCORD_TOKEN);
