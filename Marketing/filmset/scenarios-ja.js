/* Format E — 日本語. See ../FORMAT-TESTS.md §4 (T2).
 *
 * The English joke is Gen Z slang → corporate. The Japanese joke is not a translation
 * of it (GTM.md §9 forbids that) — it is **タメ口 → 敬語**, which is the same emotional
 * shape and a much sharper social taboo: sending a 部長 a message with no 敬語 at all is
 * the thing every 社会人1年目 is genuinely afraid of doing.
 *
 * So the funny half is not the slang. It is that the message is addressed to a director
 * and reads like a LINE to a friend — and the 敬語 rewrite is absurdly, comically polite.
 *
 * `corporate` is a FALLBACK only. On camera the real 敬語ボタン produces it; if latency
 * ever forces the fallback, paste back what the product actually returned.
 */
window.ME = { name: '佐藤 ゆい', initial: '佐', color: '#3D7C6B' };

window.SCENARIOS = [
  {
    id: 'ja-001',
    app: 'slack',
    situation: '上司の横文字が理解できない',
    pov: 'pov: 入社1年目、上司に送信する直前',
    // POV variants worth testing: 「pov: 敬語という概念を失った新卒」
    //   「pov: 社会人1年目、上司にタメ口で送りかけた」「pov: 22歳、上司からのSlackが全部横文字」

    workspace: 'メリディアン',
    dm: '田村 美咲',
    dmTitle: '田村 美咲',
    dmSubtitle: 'マーケティング部 部長',

    thread: [
      { from: '田村 美咲', initial: '田', color: '#B4562F', time: '昨日 11:02',
        text: 'お疲れさまです。キャンペーンの数値、共有シートにまとめておいてもらえますか？' },
      { me: true, time: '昨日 11:04', text: '承知しました！' },
      { me: true, time: '昨日 12:47', text: 'まとめました。前四半期との比較用タブも追加しています' },
      { from: '田村 美咲', initial: '田', color: '#B4562F', time: '昨日 13:15',
        text: '助かります、ありがとうございます。' },
      { from: '田村 美咲', initial: '田', color: '#B4562F', time: '昨日 16:12',
        text: '議事録も早くて助かりました。' },
      { me: true, time: '昨日 16:15', text: 'とんでもないです🙇‍♀️ 何かあればお申し付けください' },
      { me: true, time: '9:41', text: 'おはようございます！Q3の資料、いま確認しています👀' },
      {
        from: '田村 美咲', initial: '田', color: '#B4562F', time: '10:24',
        text: 'おはようございます。スコープをフィックスする前に、一度ステークホルダーと目線合わせをして、Q3のナラティブをリバイスした上でドラフトを共有しておいてもらえますか。できれば本日中に方向性だけでもいただけると助かります。'
      }
    ],

    genz: 'え、まって ガチで何言ってるか分からんのだけどw とりあえず日本語で頼むw',
    corporate: 'お疲れさまです。ご共有いただきありがとうございます。認識に齟齬があるといけませんので、いくつか確認させていただけますでしょうか。お手すきの際に5分ほどお時間をいただけますと幸いです。何卒よろしくお願いいたします。'
  }
];
