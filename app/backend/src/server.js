import cors from 'cors';
import express from 'express';
import { ensureSchema, pool, query } from './db.js';
import { metricsMiddleware, register } from './metrics.js';

const app = express();
const port = Number(process.env.PORT || 3000);

app.use(cors());
app.use(express.json());
app.use(metricsMiddleware);

app.get('/api/health', async (_req, res) => {
  try {
    await query('SELECT 1');
    res.json({ status: 'ok' });
  } catch (error) {
    res.status(503).json({ status: 'unhealthy', error: error.message });
  }
});

app.get('/api/todos', async (_req, res, next) => {
  try {
    const result = await query('SELECT id, title, completed, created_at, updated_at FROM todos ORDER BY id DESC');
    res.json(result.rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/todos', async (req, res, next) => {
  try {
    const title = String(req.body.title || '').trim();
    if (!title) {
      return res.status(400).json({ error: 'title is required' });
    }

    const result = await query(
      'INSERT INTO todos (title) VALUES ($1) RETURNING id, title, completed, created_at, updated_at',
      [title]
    );
    return res.status(201).json(result.rows[0]);
  } catch (error) {
    return next(error);
  }
});

app.put('/api/todos/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const title = String(req.body.title || '').trim();
    const completed = Boolean(req.body.completed);

    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ error: 'valid id is required' });
    }
    if (!title) {
      return res.status(400).json({ error: 'title is required' });
    }

    const result = await query(
      `UPDATE todos
       SET title = $1, completed = $2, updated_at = NOW()
       WHERE id = $3
       RETURNING id, title, completed, created_at, updated_at`,
      [title, completed, id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'todo not found' });
    }
    return res.json(result.rows[0]);
  } catch (error) {
    return next(error);
  }
});

app.delete('/api/todos/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) {
      return res.status(400).json({ error: 'valid id is required' });
    }

    const result = await query('DELETE FROM todos WHERE id = $1', [id]);
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'todo not found' });
    }
    return res.status(204).send();
  } catch (error) {
    return next(error);
  }
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.use((error, _req, res, _next) => {
  console.error(error);
  res.status(500).json({ error: 'internal server error' });
});

async function start() {
  await ensureSchema();
  app.listen(port, () => {
    console.log(`todo backend listening on ${port}`);
  });
}

start().catch((error) => {
  console.error(error);
  pool.end().finally(() => process.exit(1));
});
