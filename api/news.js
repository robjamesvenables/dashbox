export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Cache-Control', 's-maxage=300');
  try {
    const response = await fetch('https://nfs.faireconomy.media/ff_calendar_thisweek.json');
    const data = await response.json();
    // Log first item to see field names
    const high = data.filter(e => e.impact === 'High');
    res.status(200).json(high);
  } catch(e) {
    res.status(500).json({error: e.message});
  }
}
