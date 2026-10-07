export default async function handler(req, res) {
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

  try {
    const url =
      "https://api.mymemory.translated.net/get" +
      "?q=" + encodeURIComponent(text) +
      "&langpair=ja|pt";

    const response = await fetch(url);

    if (!response.ok) {
      throw new Error("Erro no serviço de tradução");
    }

    const data = await response.json();

    const translated =
      data.responseData?.translatedText || text;

    return res.status(200).json({
      original: text,
      translated: translated
    });

  } catch (error) {
    return res.status(500).json({
      error: "Não foi possível traduzir",
      details: error.message
    });
  }
}
