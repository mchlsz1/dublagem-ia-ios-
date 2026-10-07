export default function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({
      error: "Método não permitido"
    });
  }

  const text = req.body?.text;

  if (!text) {
    return res.status(400).json({
      error: "Texto não informado"
    });
  }

  return res.status(200).json({
    original: text,
    translated: text
  });
}
