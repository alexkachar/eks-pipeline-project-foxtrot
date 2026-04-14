import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

function App() {
  const [todos, setTodos] = useState([]);
  const [title, setTitle] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  async function request(path, options = {}) {
    const response = await fetch(path, {
      headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
      ...options
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.error || `Request failed: ${response.status}`);
    }
    return response.status === 204 ? null : response.json();
  }

  async function loadTodos() {
    setLoading(true);
    setError('');
    try {
      setTodos(await request('/api/todos'));
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  async function addTodo(event) {
    event.preventDefault();
    const trimmed = title.trim();
    if (!trimmed) return;
    setError('');
    try {
      const todo = await request('/api/todos', {
        method: 'POST',
        body: JSON.stringify({ title: trimmed })
      });
      setTodos((items) => [todo, ...items]);
      setTitle('');
    } catch (err) {
      setError(err.message);
    }
  }

  async function toggleTodo(todo) {
    setError('');
    try {
      const updated = await request(`/api/todos/${todo.id}`, {
        method: 'PUT',
        body: JSON.stringify({ title: todo.title, completed: !todo.completed })
      });
      setTodos((items) => items.map((item) => (item.id === todo.id ? updated : item)));
    } catch (err) {
      setError(err.message);
    }
  }

  async function deleteTodo(id) {
    setError('');
    try {
      await request(`/api/todos/${id}`, { method: 'DELETE' });
      setTodos((items) => items.filter((item) => item.id !== id));
    } catch (err) {
      setError(err.message);
    }
  }

  useEffect(() => {
    loadTodos();
  }, []);

  const openCount = todos.filter((todo) => !todo.completed).length;

  return (
    <main className="shell">
      <section className="intro">
        <p className="eyebrow">Project Foxtrot</p>
        <h1>Todos that survive the cluster.</h1>
        <p>Keep the list small, ship the platform properly.</p>
        <p>Test the CI pipeline.</p>
      </section>

      <form className="composer" onSubmit={addTodo}>
        <input
          aria-label="New todo"
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          placeholder="Add a task"
        />
        <button type="submit">Add</button>
      </form>

      <div className="status-line">
        <span>{loading ? 'Loading...' : `${todos.length} total, ${openCount} open`}</span>
        <button type="button" onClick={loadTodos}>Refresh</button>
      </div>

      {error ? <p className="error">{error}</p> : null}

      <ul className="todo-list">
        {todos.map((todo) => (
          <li key={todo.id}>
            <label>
              <input
                type="checkbox"
                checked={todo.completed}
                onChange={() => toggleTodo(todo)}
              />
              <span className={todo.completed ? 'done' : ''}>{todo.title}</span>
            </label>
            <button type="button" onClick={() => deleteTodo(todo.id)}>Delete</button>
          </li>
        ))}
      </ul>
    </main>
  );
}

createRoot(document.getElementById('root')).render(<App />);
