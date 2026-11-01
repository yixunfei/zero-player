String musicFixture({
  String title = '晴天',
  String artist = '周杰伦',
  String url = 'https://media.example/song.mp3',
  bool next = true,
}) =>
    '''
<div id="search-tracks"><ul class="playlist">
<li class="track" data-owner-id="-12" data-track-id="34" data-download="$url">
<div class="track-artist"><a>$artist</a></div>
<div class="track-title"><a>$title</a></div>
<span class="track-duration">4:29</span></li></ul></div>
<nav class="list-pagination">${next ? '<a href="/search/query?page=2">Next</a>' : ''}</nav>
''';
