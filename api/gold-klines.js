export const config = {
  regions: ['sin1'], // Singapore — Binance blocks requests from US-based servers
};

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=5');
  try {
    const interval = req.query.interval || '1m';
    const url = `https://fapi.binance.com/fapi/v1/klines?symbol=XAUUSDT&interval=${interval}&limit=100`;
    const response = await fetch(url);
    if (!response.ok) {
      const bodyText = await response.text();
      res.status(response.status).json({ error: `Binance returned ${response.status}`, detail: bodyText.slice(0, 300) });
      return;
    }
    const data = await response.json();
    res.status(200).json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}
