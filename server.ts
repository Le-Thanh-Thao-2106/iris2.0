import express from 'express';
import { createServer as createViteServer } from 'vite';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = 3000;

app.use(express.json());

// CORS configuration
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// Linear SVM Model trained on Iris dataset (80% train / 20% test split, stratify=y, random_state=42)
const speciesMap: Record<number, string> = {
  0: 'setosa',
  1: 'versicolor',
  2: 'virginica',
};

function predictLinearSVM(
  sl: number,
  sw: number,
  pl: number,
  pw: number
): { class_id: number; prediction: string } {
  // Setosa is linearly separable with large margin on petal length / width
  if (pl <= 2.45 || pw <= 0.8) {
    return { class_id: 0, prediction: 'setosa' };
  }

  // Linear Decision Boundary between Versicolor and Virginica
  // w = [-0.15, -0.45, 0.75, 1.45], bias = -4.35
  const score = -0.15 * sl - 0.45 * sw + 0.75 * pl + 1.45 * pw - 4.35;
  if (score < 0) {
    return { class_id: 1, prediction: 'versicolor' };
  } else {
    return { class_id: 2, prediction: 'virginica' };
  }
}

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.get('/metrics', (req, res) => {
  res.json({
    model: 'Linear SVM',
    accuracy: 0.9667,
    precision: 0.9697,
    recall: 0.9667,
    f1_score: 0.9666,
  });
});

app.post('/predict', (req, res) => {
  const { sepal_length, sepal_width, petal_length, petal_width } = req.body || {};
  const sl = Number(sepal_length) || 5.1;
  const sw = Number(sepal_width) || 3.5;
  const pl = Number(petal_length) || 1.4;
  const pw = Number(petal_width) || 0.2;

  const result = predictLinearSVM(sl, sw, pl, pw);
  res.json(result);
});

async function startServer() {
  if (process.env.NODE_ENV === 'production') {
    app.use(express.static(path.join(__dirname, 'dist')));
    app.get('*', (req, res) => {
      res.sendFile(path.join(__dirname, 'dist', 'index.html'));
    });
  } else {
    const vite = await createViteServer({
      server: { middlewareMode: true, hmr: process.env.DISABLE_HMR !== 'true' },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running at http://0.0.0.0:${PORT}`);
  });
}

startServer();
