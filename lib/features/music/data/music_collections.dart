import '../domain/music_recommendation.dart';

/// Editorial song lists contain search metadata only, never media addresses.
const musicCategories = ['榜单', '语种', '风格', '场景'];

final class MusicCollection {
  const MusicCollection(
    this.title,
    this.category,
    this.description,
    this.songs,
  );
  final String title, category, description;
  final List<MusicRecommendation> songs;
}

const musicCollections = {
  'mandarin': MusicCollection('华语经典', '语种', '熟悉的旋律，重温华语流行。', [
    MusicRecommendation('晴天', '周杰伦', ''),
    MusicRecommendation('十年', '陈奕迅', ''),
    MusicRecommendation('后来', '刘若英', ''),
    MusicRecommendation('倔强', '五月天', ''),
    MusicRecommendation('红豆', '王菲', ''),
    MusicRecommendation('稻香', '周杰伦', ''),
  ]),
  'cantonese': MusicCollection('粤语时光', '语种', '从经典金曲听见粤语韵味。', [
    MusicRecommendation('海阔天空', 'Beyond', ''),
    MusicRecommendation('红日', '李克勤', ''),
    MusicRecommendation('千千阕歌', '陈慧娴', ''),
    MusicRecommendation('富士山下', '陈奕迅', ''),
    MusicRecommendation('一生所爱', '卢冠廷', ''),
  ]),
  'english': MusicCollection('欧美流行', '语种', '跨越年代的英文流行精选。', [
    MusicRecommendation('Hello', 'Adele', ''),
    MusicRecommendation('Love Story', 'Taylor Swift', ''),
    MusicRecommendation('Yellow', 'Coldplay', ''),
    MusicRecommendation('Perfect', 'Ed Sheeran', ''),
    MusicRecommendation('Yesterday', 'The Beatles', ''),
  ]),
  'jazz': MusicCollection('爵士小馆', '风格', '人声与器乐交织的轻松时刻。', [
    MusicRecommendation('Take Five', 'Dave Brubeck', ''),
    MusicRecommendation('So What', 'Miles Davis', ''),
    MusicRecommendation('Fly Me to the Moon', 'Frank Sinatra', ''),
    MusicRecommendation('My Favorite Things', 'John Coltrane', ''),
  ]),
  'rock': MusicCollection('摇滚现场感', '风格', '给今天加一点鼓点与吉他。', [
    MusicRecommendation('不再犹豫', 'Beyond', ''),
    MusicRecommendation('无地自容', '黑豹乐队', ''),
    MusicRecommendation('一无所有', '崔健', ''),
    MusicRecommendation('倔强', '五月天', ''),
  ]),
  'focus': MusicCollection('专注钢琴', '场景', '适合阅读与工作的器乐选曲。', [
    MusicRecommendation('River Flows in You', 'Yiruma', ''),
    MusicRecommendation('Kiss the Rain', 'Yiruma', ''),
    MusicRecommendation('Nuvole Bianche', 'Ludovico Einaudi', ''),
    MusicRecommendation('Gymnopedie No. 1', 'Erik Satie', ''),
  ]),
  'night': MusicCollection('夜间放松', '场景', '让节奏慢下来，陪伴安静夜晚。', [
    MusicRecommendation('Come Away with Me', 'Norah Jones', ''),
    MusicRecommendation('晚安', '陈粒', ''),
    MusicRecommendation('安静', '周杰伦', ''),
    MusicRecommendation('月亮代表我的心', '邓丽君', ''),
  ]),
  'travel': MusicCollection('出发在路上', '场景', '为通勤与旅途准备的轻快选曲。', [
    MusicRecommendation('平凡之路', '朴树', ''),
    MusicRecommendation('旅行的意义', '陈绮贞', ''),
    MusicRecommendation('蓝莲花', '许巍', ''),
    MusicRecommendation('Viva La Vida', 'Coldplay', ''),
  ]),
};
