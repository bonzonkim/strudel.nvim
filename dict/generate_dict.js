const fs = require('fs');
const path = require('path');

const rawPath = path.join(__dirname, 'docs_raw.md');
const outPath = path.join(__dirname, 'strudel_docs.json');

const content = fs.readFileSync(rawPath, 'utf8');
const sections = content.split(/\n##\s+/);

const docs = {};

sections.forEach(section => {
  if (!section.trim()) return;

  const lines = section.split('\n');
  const header = lines[0].trim();
  
  // Extract names
  let names = [];
  
  // Check if header is a URL
  if (header.startsWith('https://')) {
    // Extract name from URL hash
    const hashPart = header.split('#')[1];
    if (hashPart) {
      // e.g. catcat -> cat (usually repeated?)
      // Actually in the raw file I see: https://strudel.cc/learn/factories/#catcat
      // It seems the anchor is often the name repeated or similar.
      // But I also see: https://strudel.cc/learn/synths/#basic-waveformsBasic Waveforms
      // Let's look at the next line or the header text itself.
      
      // In my raw file, I pasted:
      // ## https://strudel.cc/learn/factories/#catcat
      // The text after # is "catcat".
      // But the function is "cat".
      // Let's try to be smart.
      
      // Actually, I manually cleaned up some headers in my mind but in the file I wrote:
      // ## https://strudel.cc/learn/factories/#catcat
      
      // Let's assume the name is the part after the last / and before the hash? No.
      // The hash is #catcat.
      // Wait, in the chunks I saw: headers:{... text:"https://.../#catcat"}
      // It seems the text content of the header *is* the URL + text.
      
      // Let's look at the body.
      // Sometimes the body starts with `slowcat` (alias).
      
      // Let's try to extract from the hash.
      // If hash is "catcat", maybe it's "cat"?
      // If hash is "slowslow", it's "slow".
      // It seems the pattern is name+name?
      
      // Let's look at the raw file content I wrote.
      // ## https://strudel.cc/learn/factories/#catcat
      
      // I will try to extract the name from the hash.
      // If the hash ends with the name repeated, I'll take the half.
      // "catcat" -> "cat"
      // "slowslow" -> "slow"
      // "binarybinary" -> "binary"
      // "binarynbinaryN" -> "binaryN" (case sensitive?)
      
      // Logic: if string length is even and first half equals second half, take first half.
      // If not, maybe just take the whole thing?
      
      let candidate = hashPart;
      // Remove any trailing text that might be part of the header line but not the URL
      // In "https://.../#catcat", it's just catcat.
      // In "https://.../#basic-waveformsBasic Waveforms", hash is "basic-waveformsBasic".
      
      // Let's try to find the name in the first line of description if it's a code block?
      // No, let's stick to the hash heuristic.
      
      // Heuristic:
      // 1. Remove non-alphanumeric from end.
      // 2. Check for repetition.
      
      // Better yet, I also included manual headers like:
      // ## note
      // ## gain
      
      if (candidate) {
         // Clean candidate
         candidate = candidate.replace(/[^a-zA-Z0-9_]/g, '');
         
         if (candidate.length % 2 === 0) {
           const half = candidate.length / 2;
           if (candidate.slice(0, half).toLowerCase() === candidate.slice(half).toLowerCase()) {
             names.push(candidate.slice(0, half));
           } else {
             names.push(candidate);
           }
         } else {
            // "binarynbinaryN" -> length 13? No.
            // binaryn (7) binaryN (7) -> 14.
            // "basic-waveformsBasic" -> basicwaveformsBasic
            names.push(candidate);
         }
      }
      
    }
  } else {
    // Plain header like "note" or "vibrato, v, vib"
    // Split by comma or space
    const parts = header.split(/[,/]/).map(s => s.trim());
    names.push(...parts);
  }
  
  // Clean up names
  names = names.map(n => n.replace(/^#+\s*/, '').trim()).filter(n => n);
  
  // Extract description
  let description = [];
  let params = [];
  
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.startsWith('- ')) {
      params.push(line.substring(2));
    } else if (line.length > 0) {
      description.push(line);
    }
  }
  
  const descText = description.join(' ');
  
  names.forEach(name => {
    // Handle special case for "binarynbinaryN" -> "binaryN"
    if (name.toLowerCase().startsWith(name.slice(name.length/2).toLowerCase())) {
       name = name.slice(name.length/2);
    }
    
    // Clean up name (remove URL junk if failed)
    if (name.includes('http')) return;
    
    docs[name] = {
      description: descText,
      params: params
    };
  });
});

fs.writeFileSync(outPath, JSON.stringify(docs, null, 2));
console.log(`Generated docs for ${Object.keys(docs).length} functions.`);
