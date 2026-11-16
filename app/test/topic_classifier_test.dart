import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/topic_classifier.dart';

void main() {
  group('classifyTopics（新建卡多标签自动分类）', () {
    test('消除单字子串脏分类（吃惊/吃醋/混蛋/老奶奶/脱氧核糖核酸不进餐饮食物）', () {
      expect(classifyTopics(word: 'mengejutkan', zh: '使震惊；使吃惊'), isEmpty);
      expect(
        classifyTopics(word: 'cemburu', zh: '嫉妒；吃醋；猜忌'),
        ['情感心理'],
      );
      expect(classifyTopics(word: 'bajingan', zh: '罪犯；小偷；混蛋'), isEmpty);
      expect(
        classifyTopics(word: 'nenek', zh: '祖母；老奶奶（写作：nenek）'),
        ['家庭人际'],
      );
      expect(classifyTopics(word: 'dna', zh: '脱氧核糖核酸'), isEmpty);
    });

    test('支持一词多主题且保留真实分类', () {
      expect(
        classifyTopics(word: 'bunga', zh: '花；利息；轮胎花纹'),
        containsAll(['金融银行', '植物']),
      );
      expect(
        classifyTopics(word: 'kopi', zh: '咖啡'),
        containsAll(['餐饮食物', '饮品酒水']),
      );
      expect(classifyTopics(word: 'telur', zh: '卵；蛋'), ['餐饮食物']);
    });

    test('过滤（僻）与括号注记避免误分类', () {
      expect(
        classifyTopics(word: 'keras', zh: '硬的；盐篓（僻）；用力'),
        isEmpty,
      );
      expect(
        classifyTopics(word: 'urus', zh: '管理；料理'),
        isEmpty,
      );
    });

    test('二阶优化：DM 中心词加权与形态/中文误吸拦截', () {
      expect(classifyTopics(word: 'makan riba', zh: '放高利贷'), isEmpty);
      expect(classifyTopics(word: 'kue cincin', zh: '环状糕'), ['餐饮食物']);
      expect(classifyTopics(word: 'jalan parkir udara', zh: '机坪加固区'), ['交通出行']);
      expect(classifyTopics(word: 'bank konvensional', zh: '传统银行'), ['购物金钱']);
      expect(classifyTopics(word: 'inspeksi visual', zh: '目视检查'), isEmpty);
      expect(classifyTopics(word: 'pengotak-ngotakan', zh: '分成一格一格'), isEmpty);
      expect(classifyTopics(word: 'bertarik-tarikan', zh: '互相拉'), isEmpty);
      expect(classifyTopics(word: 'penjaringan', zh: '捕捞'), isEmpty);
      expect(classifyTopics(word: 'keterangan alat', zh: '工具状语'), isEmpty);
      expect(classifyTopics(word: 'gerakan sosial', zh: '社会运动'), isEmpty);
      expect(classifyTopics(word: 'pinjaman fonemis', zh: '语音借词'), isEmpty);
      expect(classifyTopics(word: 'bunga api', zh: '火花'), isEmpty);
    });
  });
}
