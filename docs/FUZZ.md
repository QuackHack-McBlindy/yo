# **What's the fuzz about?**


**Fuzzy matching logic**

**Levenshtein distance** ounts how many single‑character changes (insert, delete, swap) it takes to turn one word into another.  

Example: `"cat"` > `"bat"` = 1 change. The fewer changes, the more similar.  
The script turns that into a percentage (100% = identical).  



**Trigram similarity** chops each sentence into chunks of three letters: `"hello"` > `"hel"`, `"ell"`, `"llo"`.  
Then it sees how many chunks match between the two sentences.  
If many chunks are the same, the sentences are probably similar.  
This is way faster than Levenshtein, so we use it first to throw away clearly different sentences.  

* Normalize the text
* Run a quick trigram check – if similarity is below 30% we skip it.
* For the rest, calculate the Levenshtein percentage.  
* Keep the sentence with the highest score.

<br>
