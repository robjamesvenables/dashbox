export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=5');
  try {
    const interval = req.query.interval || '1m';
    const url = `https://fapi.binance.com/fapi/v1/klines?symbol=XAUUSDT&interval=${interval}&limit=100`;
    const response = await fetch(url);
    const data = await response.json();
    res.status(200).json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}
