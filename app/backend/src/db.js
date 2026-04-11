import pg from 'pg';
import { dbQueryDuration } from './metrics.js';

const { Pool } = pg;

const useSsl = process.env.DB_SSL !== 'false';

export const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'todo',
  password: process.env.DB_PASSWORD || 'todo',
  database: process.env.DB_NAME || 'todo',
  ssl: useSsl ? { rejectUnauthorized: false } : false,
  max: Number(process.env.DB_POOL_SIZE || 10)
});

export async function query(text, params = []) {
  const endTimer = dbQueryDuration.startTimer({ operation: text.split(/\s+/)[0].toLowerCase() });
  try {
    return await pool.query(text, params);
  } finally {
    endTimer();
  }
}

export async function ensureSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS todos (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      completed BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);
}
