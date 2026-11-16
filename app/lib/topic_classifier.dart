library;

final RegExp _kParensRe = RegExp(r'[（(][^）)]*[）)]');
final RegExp _kClauseSplitRe = RegExp(r'[、，,/]+');
final RegExp _kTokRe = RegExp(r'[^a-z]+');

const Set<String> _kSafe1 = {
  '买', '云', '借', '债', '兵', '刀', '医', '卖', '吃', '哭', '喝', '国', '奶', '山', '岛', '庙', '怒', '怕', '战', '拜', '杯', '枪', '树', '河', '洗', '海', '炮', '牛', '狗', '猫', '王', '病', '盐', '睡', '碗', '票', '税', '笑', '米', '糖', '羊', '肉', '船', '花', '茶', '药', '蛋', '贵', '车', '辣', '酒', '钱', '锅', '雨', '风', '饭', '饱', '饿', '马', '鱼', '鸟', '鸡'
};

const List<String> _kPre = [
  'me', 'mem', 'men', 'meng', 'meny', 'di', 'ter', 'ber', 'pe', 'pem', 'pen', 'peng', 'peny', 'per', 'se', 'ke', 'memper', 'member'
];
const List<String> _kSuf = [
  'an', 'kan', 'nya', 'lah', 'i'
];

const Set<String> _kVariantBlock = {
  'tarikan', 'pengotak', 'mengotak', 'penjaringan'
};

const Set<String> _kPolysemousHeads = {
  'makan', 'buah', 'bunga', 'mata', 'kaki', 'kepala', 'tangan', 'hati',
  'anak', 'air', 'jalan', 'main', 'naik', 'turun', 'buka', 'tutup',
  'pakai', 'cuci', 'potong', 'bakar', 'taruh', 'letak', 'minyak', 'batu',
  'angin', 'panas', 'asam', 'kartu', 'perang', 'pinjam', 'pinjaman',
  'daya', 'energi', 'surat', 'kerja', 'buku', 'garis', 'ikan', 'ayam',
  'laut', 'hutan', 'tanah', 'rumah', 'uang', 'hukum', 'bahasa', 'sistem',
  'alam',
};

const Map<String, List<String>> _kNeg = {
  '料理': ['管理', '处理', '办理', '照料', '打理', '家务'],
  '味道': ['趣味', '意味', '韵味'],
  '水果': ['果汁'],
  '工作': ['工作室', '工作坊'],
  '关系': ['没关系'],
  '开心': ['开玩笑'],
  '医院': ['兽医'],
  '动物': ['动植物'],
  '植物': ['动植物'],
  '数字': ['数字化', '数字版'],
  '时间': ['长时间', '短时间', '第一时间'],
  '天气': ['生气', '脾气'],
  '电话': ['打电话'],
  '工具': ['工具状语', '工具词', '工具格', '交通工具', '运输工具', '支付工具', '金融工具'],
  '运动': ['社会运动', '政治运动', '学生运动', '解放运动', '独立运动', '反抗运动', '群众运动', '民主运动', '革命运动', '环保运动', '妇女运动', '工人运动', '宗教运动', '机械运动', '天体运动', '布朗运动', '相对运动', '热运动'],
  '计算': ['计算机', '计算在内', '包括在内', '微计算'],
  '营养': ['营养生长', '营养繁殖', '无性繁殖'],
};

const List<({String name, List<String> idKw, List<String> zhKw})> _kTopics = [
  (name: '日常起居', idKw: ['bangun', 'tidur', 'mandi', 'cuci', 'sikat', 'sisir', 'pakai', 'buka', 'tutup', 'duduk', 'berdiri', 'letak', 'taruh', 'bersih', 'kotor', 'rumah', 'kamar', 'dapur', 'kunci', 'lampu', 'sapu', 'jemur', 'lipat', 'potong', 'belah', 'aduk', 'rebus', 'goreng', 'seduh'], zhKw: ['睡', '起床', '洗澡', '洗', '刷牙', '梳理', '打开', '关上', '关', '坐', '站', '放下', '干净', '脏', '房间', '厨房', '钥匙', '灯', '打扫', '晾晒', '折叠', '切', '煮', '炒', '烧', '家务', '日常']),
  (name: '餐饮食物', idKw: ['makan', 'minum', 'nasi', 'roti', 'daging', 'ayam', 'ikan', 'sayur', 'buah', 'gula', 'garam', 'kopi', 'teh', 'susu', 'masak', 'resep', 'restoran', 'warung', 'lapar', 'kenyang', 'manis', 'asin', 'pedas', 'pahit', 'asam', 'sambal', 'kue', 'mie', 'sate', 'bakar', 'hidangan', 'sarapan', 'sendok', 'piring', 'gelas', 'cangkir', 'keju', 'permen'], zhKw: ['吃', '喝', '饭', '面', '面包', '肉', '鱼', '菜', '水果', '糖', '盐', '咖啡', '茶', '牛奶', '汤', '味道', '甜', '咸', '辣', '苦', '酸', '饿', '饱', '餐', '厨', '食', '饮', '料理', '小吃', '点心', '米饭', '鸡', '蛋', '奶', '锅', '碗', '杯', '勺', '盘', '奶酪', '乳酪', '糖果', '好吃', '美味', '喝醉', '醉酒', '蛋糕', '饼干', '巧克力', '冰淇淋', '果汁', '豆浆', '早餐', '午餐', '晚餐', '早饭', '午饭', '晚饭', '夜宵']),
  (name: '旅行观光', idKw: ['wisata', 'liburan', 'hotel', 'penginapan', 'tiket', 'paspor', 'visa', 'bandara', 'stasiun', 'peta', 'koper', 'kunjung', 'pantai', 'candi', 'museum', 'pesan', 'pemandu', 'turis', 'perjalanan', 'tamasya'], zhKw: ['旅行', '旅游', '游客', '酒店', '旅馆', '票', '护照', '签证', '机场', '车站', '地图', '行李', '预订', '参观', '景点', '海滩', '寺庙', '博物', '导游', '度假', '行程']),
  (name: '交通出行', idKw: ['mobil', 'motor', 'sepeda', 'bus', 'kereta', 'pesawat', 'kapal', 'taksi', 'ojek', 'angkot', 'kemudi', 'bensin', 'tiba', 'berangkat', 'naik', 'turun', 'jalan', 'lalu lintas', 'lampu merah', 'pelabuhan', 'terminal', 'parkir', 'menyetir', 'penumpang'], zhKw: ['汽车', '摩托', '自行', '公交', '火车', '飞机', '轮船', '出租', '驾车', '驾驶', '汽油', '到达', '出发', '乘坐', '上车', '下车', '道路', '红绿灯', '码头', '港口', '停车', '乘客', '司机', '堵车', '交通', '车', '船', '票']),
  (name: '购物金钱', idKw: ['beli', 'jual', 'harga', 'uang', 'bayar', 'toko', 'pasar', 'diskon', 'mahal', 'murah', 'bank', 'tabung', 'pinjam', 'utang', 'pajak', 'gaji', 'untung', 'rugi', 'biaya', 'ongkos', 'kredit', 'cicil', 'tawar', 'kembalian', 'dompet', 'rekening'], zhKw: ['买', '卖', '价格', '价钱', '钱', '付款', '商店', '市场', '折扣', '贵', '便宜', '银行', '存款', '借', '债', '税', '工资', '利润', '亏', '费用', '分期', '还价', '钱包', '账户', '货币', '交易', '购物', '消费', '收银', '找零']),
  (name: '金融银行', idKw: ['rekening', 'tabungan', 'setor', 'tarik tunai', 'transfer', 'saldo', 'tagihan', 'cicilan', 'angsuran', 'bunga', 'pinjaman', 'agunan', 'deposito', 'giro', 'kliring', 'kurs', 'valuta', 'tunai', 'kartu', 'atm', 'teller', 'transaksi', 'pembayaran', 'struk', 'kwitansi', 'dompet digital', 'valas', 'denda', 'jatuh tempo'], zhKw: ['账户', '账号', '存款', '取款', '取现', '转账', '汇款', '余额', '账单', '分期', '贷款', '借款', '利息', '手续费', '信用卡', '借记卡', '银行卡', '取款机', '柜员', '现金', '零钱', '纸币', '硬币', '汇率', '外币', '兑换', '交易', '额度', '抵押', '到期', '缴费', '收款', '对账']),
  (name: '医疗就医', idKw: ['dokter', 'rumah sakit', 'klinik', 'puskesmas', 'apotek', 'obat', 'resep', 'periksa', 'perawat', 'bidan', 'pasien', 'vaksin', 'imunisasi', 'demam', 'batuk', 'pilek', 'sakit', 'nyeri', 'luka', 'operasi', 'darah', 'laboratorium', 'ambulans', 'gawat', 'rawat', 'sembuh', 'penyakit', 'infeksi', 'alergi', 'dosis', 'suntik', 'tekanan darah', 'gula darah', 'rontgen'], zhKw: ['医院', '医生', '大夫', '诊所', '护士', '病人', '患者', '药房', '处方', '挂号', '门诊', '住院', '打针', '输液', '化验', '体检', '体温', '血压', '血糖', '发烧', '咳嗽', '感冒', '疼痛', '伤口', '手术', '疫苗', '接种', '急诊', '救护车', '病房', '症状', '疾病', '过敏', '剂量', '康复', '复查', '转诊', '忌口', '药', '病', '医']),
  (name: '政务证件', idKw: ['ktp', 'sim', 'paspor', 'visa', 'akta', 'kartu keluarga', 'penduduk', 'kependudukan', 'domisili', 'izin', 'surat', 'formulir', 'berkas', 'pengajuan', 'permohonan', 'meterai', 'legalisir', 'imigrasi', 'kelurahan', 'kecamatan', 'instansi', 'layanan', 'pengaduan', 'npwp', 'tanda tangan', 'sidik jari', 'fotokopi', 'kuasa', 'pengantar', 'persyaratan', 'verifikasi', 'pajak', 'warga', 'antrean', 'loket'], zhKw: ['身份证', '护照', '签证', '户口', '户籍', '证明', '证件', '申请表', '表格', '材料', '申请', '提交', '盖章', '公证', '移民局', '税务局', '派出所', '办事处', '政府', '公务员', '签名', '指纹', '复印件', '委托书', '许可', '审批', '登记', '排队', '窗口', '居民', '公所', '手续', '归档', '盖章处']),
  (name: '通讯网络', idKw: ['telepon', 'ponsel', 'pulsa', 'kuota', 'internet', 'wifi', 'sinyal', 'jaringan', 'unduh', 'unggah', 'aplikasi', 'akun', 'sandi', 'pesan', 'panggilan', 'kontak', 'nomor', 'kartu sim', 'baterai', 'layar', 'tangkapan', 'siaran', 'tautan', 'verifikasi', 'pembaruan', 'memori', 'penyimpanan', 'nada', 'mode pesawat', 'data seluler', 'berbagi'], zhKw: ['电话', '手机', '话费', '流量', '网络', '信号', '下载', '上传', '应用', '软件', '账号', '密码', '验证码', '消息', '短信', '来电', '通话', '通讯录', '联系人', '号码', '电池', '充电', '充电器', '屏幕', '截屏', '直播', '链接', '更新', '内存', '存储', '铃声', '震动', '无线', '蓝牙', '耳机', '套餐', '上网', '连接', '密码']),
  (name: '工作职场', idKw: ['kerja', 'kantor', 'pegawai', 'karyawan', 'atasan', 'rapat', 'tugas', 'jabatan', 'kontrak', 'wawancara', 'proyek', 'perusahaan', 'usaha', 'profesi', 'lembur', 'rekan', 'pimpinan', 'sekretaris', 'berhenti kerja', 'melamar', 'upah'], zhKw: ['工作', '办公', '职业', '员工', '老板', '上司', '会议', '任务', '合同', '面试', '项目', '公司', '事业', '专业', '岗位', '同事', '加班', '简历', '应聘', '辞职', '领导', '秘书', '薪水']),
  (name: '时间日历', idKw: ['waktu', 'hari', 'minggu', 'bulan', 'tahun', 'jam', 'menit', 'detik', 'pagi', 'siang', 'sore', 'malam', 'kemarin', 'besok', 'sekarang', 'nanti', 'dulu', 'awal', 'akhir', 'sering', 'jarang', 'zaman', 'masa', ' tanggal', 'musim', 'sebentar', 'selamanya'], zhKw: ['时间', '小时', '分钟', '秒钟', '早上', '上午', '中午', '下午', '晚上', '昨天', '明天', '现在', '以后', '从前', '开始', '结束', '经常', '很少', '时代', '季节', '日期', '永远', '一会儿', '暂时']),
  (name: '情感心理', idKw: ['cinta', 'sayang', 'rindu', 'senang', 'sedih', 'marah', 'takut', 'malu', 'bangga', 'kecewa', 'harap', 'khawatir', 'gembira', 'benci', 'sabar', 'tenang', 'gelisah', 'bahagia', 'emosi', 'hati', 'cemburu', 'terharu', 'kesal', 'putus asa', 'berani'], zhKw: ['爱情', '恋爱', '想念', '高兴', '开心', '伤心', '难过', '生气', '发怒', '害怕', '害羞', '骄傲', '自豪', '失望', '希望', '担心', '快乐', '讨厌', '耐心', '平静', '焦虑', '幸福', '情绪', '嫉妒', '勇敢', '沮丧', '感激', '哭', '笑', '怒', '怕']),
  (name: '身体健康', idKw: ['sakit', 'obat', 'dokter', 'rumah sakit', 'demam', 'batuk', 'pilek', 'luka', 'pemeriksaan medis', 'sembuh', 'sehat', 'vaksin', 'perawat', 'hamil', 'darah', 'jantung', 'otak', 'paru', 'lambung', 'ginjal', 'tulang', 'otot', 'kulit', 'gejala', 'resep dokter', 'operasi'], zhKw: ['疾病', '生病', '药', '医生', '医院', '发烧', '咳嗽', '感冒', '伤口', '体检', '身体检查', '医疗检查', '痊愈', '健康', '疫苗', '护士', '怀孕', '治疗', '症状', '手术', '血压', '营养', '疼', '痛', '病']),
  (name: '身体部位', idKw: ['wajah', 'mata', 'hidung', 'mulut', 'telinga', 'tangan', 'kaki', 'kepala', 'rambut', 'gigi', 'lidah', 'kulit', 'darah', 'jantung', 'otak', 'perut', 'punggung', 'leher', 'jari', 'lutut', 'bahu', 'dada', 'tulang', 'otot', 'bibir', 'dahi', 'pipi', 'kuku', 'siku', 'pinggang'], zhKw: ['眼睛', '鼻子', '耳朵', '牙齿', '舌头', '皮肤', '心脏', '大脑', '肚子', '脖子', '手指', '膝盖', '肩膀', '骨头', '肌肉', '嘴唇', '额头', '脸颊', '指甲', '头发', '身体', '脸部']),
  (name: '家庭人际', idKw: ['keluarga', 'ayah', 'ibu', 'anak', 'kakak', 'adik', 'saudara', 'nenek', 'kakek', 'suami', 'istri', 'orang tua', 'teman', 'sahabat', 'tetangga', 'pacar', 'kerabat', 'paman', 'bibi', 'sepupu', 'menikah', 'kawin', 'lahir', 'panggil'], zhKw: ['家庭', '父亲', '妈妈', '母亲', '儿子', '女儿', '哥哥', '弟弟', '姐姐', '妹妹', '兄弟', '姐妹', '祖母', '祖父', '奶奶', '爷爷', '丈夫', '妻子', '夫妻', '朋友', '邻居', '亲戚', '叔叔', '阿姨', '表兄', '结婚', '出生', '父母', '孩子', '大人']),
  (name: '自然万物', idKw: ['laut', 'bumi', 'tanah', 'banjir', 'udara', 'cuaca', 'alam', 'lingkungan', 'ekosistem', 'alam liar', 'langit', 'matahari', 'bulan', 'bintang', 'hujan', 'angin'], zhKw: ['海洋', '河流', '地球', '泥土', '空气', '自然', '野生', '海', '河', '环境', '生态', '潮', '浪', '天空', '月亮', '太阳', '星星', '大自然', '山水']),
  (name: '学习教育', idKw: ['belajar', 'mengajar', 'sekolah', 'guru', 'murid', 'mahasiswa', 'dosen', 'kuliah', 'buku', 'pelajaran', 'ujian', 'nilai', 'kelas', 'ilmu', 'tulis', 'baca', 'hitung', 'bahasa', 'kamus', 'pustaka', 'perpustakaan', 'gelar', 'sarjana', 'hafal', 'terjemah'], zhKw: ['学习', '教学', '学校', '老师', '教师', '学生', '大学生', '课程', '大学', '书', '课本', '考试', '分数', '成绩', '班级', '知识', '阅读', '计算', '语言', '词典', '图书馆', '学位', '学士', '背诵', '翻译', '作业', '研究', '专业', '教室', '讲台']),
  (name: '政法军事', idKw: ['negara', 'pemerintah', 'presiden', 'menteri', 'rakyat', 'warga', 'hukum', 'undang-undang', 'pilih', 'partai', 'tentara', 'perang', 'damai', 'hak', 'kewajiban', 'pajak', 'pengadilan', 'hakim', 'polisi', 'duta', 'kabinet', 'sidang', 'aturan'], zhKw: ['国家', '政府', '总统', '部长', '人民', '公民', '法律', '法令', '选举', '政党', '军队', '士兵', '战争', '和平', '权利', '义务', '政治', '政策', '法院', '法官', '警察', '外交', '内阁', '规定', '国', '王', '兵', '枪', '炮', '战']),
  (name: '科技工程', idKw: ['mesin', 'listrik', 'alat', 'ukur', 'kabel', 'baterai', 'layar', 'perangkat', 'rekayasa', 'pabrik', 'logam', 'elektronika', 'energi', 'senjata', 'amunisi', 'turbin', 'genset', 'panel'], zhKw: ['机器', '电力', '能源', '设备', '测量', '技术', '工程', '工厂', '金属', '电子', '电池', '电缆', '武器', '电器', '发电', '机械', '仪器', '仪表', '装配', '零件']),
  (name: '宗教信仰', idKw: ['tuhan', 'allah', 'doa', 'sembahyang', 'masjid', 'gereja', 'pura', 'kitab', 'iman', 'suci', 'malaikat', 'nabi', 'puasa', 'ibadah', 'khotbah', 'pendeta', 'ustad', 'surga', 'neraka', 'dosa', 'berkah'], zhKw: ['上帝', '真主', '祈祷', '清真寺', '教堂', '寺庙', '经文', '信仰', '神圣', '天使', '先知', '斋戒', '礼拜', '牧师', '天堂', '地狱', '罪', '祝福', '宗教', '庙', '拜', '伊斯兰', '基督教', '佛教']),
  (name: '服饰穿着', idKw: ['baju', 'celana', 'kemeja', 'sepatu', 'topi', 'kain', 'sarung', 'rok', 'jaket', 'kaos', 'sandal', 'ikat pinggang', 'jahit', 'benang', 'kancing', 'saku', 'seragam', 'perhiasan', 'cincin', 'kalung'], zhKw: ['衣服', '裤子', '衬衫', '鞋子', '帽子', '布料', '裙子', '外套', '穿衣', '穿着', '穿上', '穿戴', '凉鞋', '腰带', '缝制', '纽扣', '口袋', '制服', '首饰', '戒指', '项链']),
  (name: '文体娱乐', idKw: ['musik', 'lagu', 'nyanyi', 'tari', 'gambar', 'lukis', 'film', 'main', 'bola', 'lomba', 'pertandingan', 'menang', 'kalah', 'juara', 'renang', 'lari', 'sepak bola', 'bulu tangkis', 'piano', 'gitar', 'drama'], zhKw: ['音乐', '歌曲', '唱歌', '跳舞', '画', '绘画', '电影', '游戏', '玩', '球', '比赛', '赢', '输', '冠军', '游泳', '跑', '足球', '羽毛球', '钢琴', '吉他', '戏剧', '艺术', '运动', '娱乐', '摄影']),
  (name: '天气气候', idKw: ['cuaca', 'hujan', 'gerimis', 'badai', 'angin', 'awan', 'kabut', 'embun', 'salju', 'es', 'petir', 'kilat', 'guntur', 'pelangi', 'banjir', 'kekeringan', 'gempa', 'tsunami', 'gunung api', 'suhu', 'panas', 'dingin', 'lembap', 'musim'], zhKw: ['天气', '下雨', '雨', '暴雨', '风', '云', '雾', '露', '雪', '冰', '雷', '闪电', '彩虹', '洪水', '干旱', '地震', '海啸', '火山', '气温', '温度', '炎热', '寒冷', '潮湿', '气候', '阴天', '晴天']),
  (name: '农业渔业', idKw: ['tani', 'sawah', 'ladang', 'tanam', 'panen', 'benih', 'bibit', 'pupuk', 'irigasi', 'ternak', 'kandang', 'nelayan', 'jala', 'pancing', 'tambak', 'tebang'], zhKw: ['农业', '农民', '稻田', '田', '种植', '播种', '收割', '收获', '种子', '秧苗', '肥料', '灌溉', '养殖', '畜牧', '渔民', '捕鱼', '渔网', '钓鱼', '鱼塘', '砍伐', '庄稼']),
  (name: '数学计量', idKw: ['angka', 'hitung', 'tambah', 'kurang', 'jumlah', 'garis', 'sudut', 'ukur', 'timbang', 'skala', 'desimal', 'pecahan', 'persen', 'rata-rata', 'rumus', 'geometri'], zhKw: ['数学', '数字', '加法', '减法', '乘法', '除法', '等于', '计算', '总数', '合计', '平均', '百分', '小数', '分数', '公式', '几何', '角度', '测量', '称重', '尺寸', '刻度', '倍数', '一半']),
  (name: '物理', idKw: ['listrik', 'magnet', 'energi', 'cahaya', 'gelombang', 'radiasi', 'atom', 'fisika', 'nuklir', 'optik', 'daya', 'tegangan', 'medan', 'gravitasi', 'relativitas', 'kuark', 'partikel', 'prisma', 'lensa'], zhKw: ['物理', '电力', '电流', '电压', '导电', '磁场', '磁铁', '能量', '光线', '光源', '光波', '辐射', '原子', '粒子', '核能', '力学', '光学', '波的', '电荷', '放电', '静电', '光谱', '折射', '反射']),
  (name: '化学', idKw: ['kimia', 'molekul', 'unsur', 'reaksi', 'asam', 'basa', 'gas', 'larutan', 'oksidasi', 'senyawa', 'logam', 'katalis', 'polutan', 'alkohol', 'pestisida', 'zat'], zhKw: ['化学', '元素', '分子', '化合物', '酸', '碱', '合金', '腐蚀', '溶液', '氧化', '催化', '化学反', '气体', '液体', '固体', '蒸汽', '化学物', '有毒物']),
  (name: '天文宇宙', idKw: ['planet', 'orbit', 'galaksi', 'gerhana', 'teleskop', 'meteor', 'komet', 'tata surya', 'rasi', 'asteroid', 'satelit alam'], zhKw: ['天文', '宇宙', '行星', '恒星', '卫星', '彗星', '流星', '陨石', '星系', '星座', '轨道', '月食', '日食', '太空', '银河', '天体', '星际', '望远镜']),
  (name: '计算机网络', idKw: ['komputer', 'internet', 'program', 'data', 'jaringan', 'aplikasi', 'sistem', 'digital', 'perangkat lunak', 'perangkat keras', 'laptop', 'gawai', 'ponsel', 'daring', 'luring', 'media sosial', 'kamera', 'berkas', 'unduh', 'unggah', 'papan ketik', 'prosesor', 'memori'], zhKw: ['电脑', '计算机', '网络', '程序', '数据', '软件', '硬件', '屏幕', '信号', '电池', '电缆', '充电', '下载', '上传', '账号', '密码', '网址', '网页', '线上', '离线', '应用程', '社交媒体', '社交网络', '人工智能', '算法', '代码', '编程', '路由', '截图', '视频', '音频', '电子邮', '聊天']),
  (name: '科学研究', idKw: ['laboratorium', 'penelitian', 'ilmu', 'teori', 'eksperimen', 'hipotesis', 'metode', 'analisis', 'observasi', 'karya ilmiah', 'jurnal', 'abstrak', 'statistika', 'aljabar', 'geometri', 'kalkulus', 'matematika', 'biologi', 'geologi', 'astronomi'], zhKw: ['实验室', '研究', '科学', '理论', '实验', '观测', '分析', '定律', '公式', '常数', '样本', '变量', '论文', '学术', '推理', '假说', '考证']),
  (name: '工程技术', idKw: ['rekayasa', 'teknik', 'mesin', 'turbin', 'genset', 'konstruksi alat', 'rangka', 'poros', 'bantalan', 'pengelasan'], zhKw: ['工程技术', '工程学', '机械', '引擎', '焊接', '轴承', '发电', '工厂', '施工设备']),
  (name: '动物', idKw: ['hewan', 'anjing', 'kucing', 'burung', 'ular', 'harimau', 'gajah', 'monyet', 'kambing', 'kuda', 'sapi', 'tikus', 'katak', 'hiu', 'paus', 'lumba-lumba', 'kupu-kupu', 'lebah', 'semut', 'buaya', 'cicak', 'elang', 'merpati', 'bangau', 'kancil', 'rusa'], zhKw: ['动物', '野兽', '鸟类', '鱼类', '昆虫', '蝴蝶', '蜜蜂', '蚂蚁', '鲨鱼', '鲸鱼', '海豚', '青蛙', '乌龟', '骆驼', '袋鼠', '狮子', '老虎', '大象', '猴子', '山羊', '绵羊', '公鸡', '母鸡', '鸭子', '老鹰', '鹦鹉', '乌鸦', '蝙蝠', '刺猬', '松鼠', '幼虫', '毛虫', '害虫', '爬虫', '哺乳动物', '猎豹', '鳄鱼', '海龟', '物种']),
  (name: '植物', idKw: ['tumbuhan', 'pohon', 'bunga', 'daun', 'akar', 'hutan', 'rumput', 'bambu', 'tunas', 'batang', 'kelapa', 'beringin', 'anggrek', 'mangga', 'jati'], zhKw: ['植物', '树木', '森林', '花朵', '花草', '树叶', '树根', '树干', '竹', '藤', '木材', '嫩芽', '灌木', '苔藓', '蕨类', '果园', '光合']),
  (name: '地质水文', idKw: ['gempa', 'gunung', 'sungai', 'danau', 'pulau', 'lembah', 'selat', 'teluk', 'delta', 'tsunami', 'tanah', 'batu', 'pasir', 'gunung api', 'sumber air', 'sungai besar', 'tambang', 'bukit', 'galian'], zhKw: ['地质', '地震', '火山', '岩石', '矿物', '土壤', '河流', '水源', '地下水面', '地下水', '海湾', '半岛', '岛屿', '三角洲', '潮汐', '支流', '山谷', '平原', '高原', '盆地', '溶洞', '基岩', '断层', '山丘', '丘陵', '矿山', '矿场', '采矿', '钻井', '山崖', '地基']),
  (name: '烹饪厨艺', idKw: ['masak', 'resep', 'bumbu', 'goreng', 'rebus', 'tumis', 'panggang', 'kukus', 'cincang', 'adonan', 'perasan'], zhKw: ['烹饪', '厨艺', '食谱', '调味', '腌制', '佐料', '火候', '翻炒', '切块', '剁', '蒸笼', '煎']),
  (name: '饮品酒水', idKw: ['kopi', 'teh', 'jus', 'minuman', 'bir', 'soda', 'es teh', 'air mineral'], zhKw: ['咖啡', '茶', '果汁', '酒', '饮料', '奶茶', '牛奶', '饮用水', '汽水', '啤酒', '葡萄酒', '冰镇', '解渴']),
  (name: '食材调料', idKw: ['bumbu', 'bahan', 'daging', 'beras', 'gula', 'garam', 'minyak', 'tepung', 'sayur', 'buah', 'sambal', 'kaldu'], zhKw: ['食材', '原料', '香料', '面粉', '调味料', '食用油', '配料', '淀粉', '蜂蜜', '奶油', '馅']),
  (name: '通信传媒', idKw: ['telepon', 'pesan', 'surat', 'kirim', 'terima', 'pos', 'perangko', 'koran', 'majalah', 'berita', 'siaran', 'jaringan', 'internet', 'sinyal', 'alamat', 'kontak', 'wawancara', 'lapor', 'cetak'], zhKw: ['电话', '手机', '短信', '消息', '信件', '邮件', '寄', '发送', '接收', '邮票', '报纸', '杂志', '新闻', '广播', '电视节目', '网络', '信号', '地址', '联系', '采访', '报道', '印刷', '传媒']),
  (name: '城市建筑', idKw: ['gedung', 'menara', 'jembatan', 'bata', 'semen', 'beton', 'atap', 'pilar', 'renovasi', 'bangun', 'bongkar', 'arsitek', 'kota', 'desa', 'trotoar', 'drainase', 'kuburan', 'monumen', 'istana'], zhKw: ['城市', '都市', '乡村', '农村', '建筑', '大楼', '楼房', '塔', '桥', '砖', '水泥', '混凝土', '屋顶', '柱子', '装修', '建造', '拆除', '建筑师', '街道', '人行道', '排水', '宫殿', '纪念碑', '工地']),
  (name: '工具材料', idKw: ['palu', 'paku', 'sekrup', 'obeng', 'gergaji', 'kikir', 'amplas', 'tali', 'kawat', 'rantai', 'kayu', 'besi', 'baja', 'plastik', 'karet', 'lem', 'mesin', 'gerinda', 'bor'], zhKw: ['工具', '锤', '钉子', '螺丝', '扳手', '起子', '锯', '锉', '砂纸', '绳子', '铁丝', '链条', '木头', '铁', '钢', '塑料', '橡胶', '胶水', '机器', '钻', '材料', '原料']),
  (name: '战争冲突', idKw: ['perang', 'senjata', 'meriam', 'peluru', 'bom', 'tempur', 'serang', 'pertahanan', 'musuh', 'menyerah', 'gencatan', 'perdamaian', 'benteng', 'markas', 'pasukan', 'invasi', 'revolusi'], zhKw: ['战争', '打仗', '武器', '枪', '炮', '子弹', '炸弹', '轰炸', '进攻', '攻击', '防御', '敌人', '投降', '停战', '和平', '堡垒', '基地', '部队', '入侵', '革命', '冲突']),
  (name: '节日庆典', idKw: ['hari raya', 'festival', 'upacara', 'pesta', 'arakan', 'kembang api', 'lomba', 'hadiah', 'adat', 'tradisi', 'pengantin', 'melamar', 'lamaran', 'pernikahan'], zhKw: ['节日', '庆祝', '典礼', '仪式', '宴会', '派对', '烟花', '游行', '传统节日', '传统仪式', '传统习俗', '民俗', '习俗', '婚礼', '新娘', '新郎', '求婚', '彩礼', '纪念日', '贺礼', '周年']),
  (name: '性格品质', idKw: ['rajin', 'malas', 'jujur', 'curang', 'pelit', 'pemberani', 'penakut', 'ramah', 'sombong', 'rendah hati', 'sabar', 'punya malu', 'tegang', 'setia', 'pengkhianat', 'pendiam', 'cerewet', 'penyabar'], zhKw: ['勤劳', '懒惰', '诚实', '虚伪', '撒谎', '吝啬', '小气', '大方', '友善', '友好', '骄傲', '谦虚', '聪明', '愚蠢', '笨', '认真', '马虎', '忠诚', '背叛', '内向', '外向', '话多', '性格', '脾气', '品质']),
];

final Map<String, Set<String>> _varCache = {};

Set<String> _variantsOf(String k) {
  return _varCache.putIfAbsent(k, () {
    if (k.contains(' ')) return {k};
    final v = <String>{k};
    final hasSuf =
        (k.endsWith('an') || k.endsWith('kan') || k.endsWith('i')) &&
        k.length > 4;
    if (!hasSuf) {
      for (final p in _kPre) {
        for (final cand in ['$p$k', '$p${k}an', '$p${k}kan']) {
          if (!_kVariantBlock.contains(cand)) v.add(cand);
        }
      }
    }
    for (final s in _kSuf) {
      final cand = '$k$s';
      if (!_kVariantBlock.contains(cand)) v.add(cand);
      if (!hasSuf) {
        for (final p in _kPre) {
          final cand2 = '$p$k$s';
          if (!_kVariantBlock.contains(cand2)) v.add(cand2);
        }
      }
    }
    return v;
  });
}

const _kVowels = {'a', 'e', 'i', 'o', 'u'};

int _scoreId(String word, List<String> kws) {
  final w = word.trim().toLowerCase();
  if (w.isEmpty) return 0;
  if (!w.contains(' ')) {
    final toks = w.split(_kTokRe).where((t) => t.isNotEmpty).toList();
    if (toks.isEmpty) return 0;
    final tokSet = toks.toSet();
    final isAsymRedup =
        w.contains('-') && toks.length == 2 && toks[0] != toks[1];
    for (final kw in kws) {
      if (kw.contains(' ')) continue;
      final vs = _variantsOf(kw);
      if (tokSet.intersection(vs).isNotEmpty) {
        if (isAsymRedup &&
            _kVowels.contains(kw[0]) &&
            toks[0] != kw &&
            (toks[1].startsWith('ng') || toks[1].startsWith('ny')) &&
            !vs.contains(toks[1])) {
          continue;
        }
        return 100;
      }
    }
    return 0;
  }

  final segTokens = <List<String>>[];
  for (final seg in w.split(RegExp(r'\s+'))) {
    final ts = seg.split(_kTokRe).where((t) => t.isNotEmpty).toList();
    if (ts.isNotEmpty) segTokens.add(ts);
  }
  if (segTokens.isEmpty) return 0;
  final flat = segTokens.map((ts) => ts.join(' ')).join(' ');
  final headToks = segTokens.first.toSet();
  final modToks = <String>{};
  for (var i = 1; i < segTokens.length; i++) {
    modToks.addAll(segTokens[i]);
  }

  var hasSoft = false;
  final softPositions = <int>{};
  for (final kw in kws) {
    if (kw.contains(' ')) {
      if (RegExp('\\b${RegExp.escape(kw)}\\b').hasMatch(flat)) return 100;
      continue;
    }
    final vs = _variantsOf(kw);
    final inHead = headToks.intersection(vs).isNotEmpty;
    final inMod = modToks.intersection(vs).isNotEmpty;
    if (inHead && !_kPolysemousHeads.contains(kw)) {
      return 100;
    }
    if (inHead || inMod) {
      hasSoft = true;
      if (inHead) softPositions.add(0);
      for (var i = 1; i < segTokens.length; i++) {
        if (segTokens[i].toSet().intersection(vs).isNotEmpty) {
          softPositions.add(i);
        }
      }
    }
  }
  if (softPositions.length >= 2) return 100;
  return hasSoft ? 50 : 0;
}

List<String> _cleanZhClauses(String zh) {
  if (zh.trim().isEmpty) return const [];
  final segs = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < zh.length; i++) {
    final ch = zh[i];
    if (ch == '（' || ch == '(') {
      depth++;
    } else if (ch == '）' || ch == ')') {
      if (depth > 0) depth--;
    } else if (depth == 0 && (ch == '；' || ch == ';')) {
      final s = zh.substring(start, i).trim();
      if (s.isNotEmpty) segs.add(s);
      start = i + 1;
    }
  }
  final tail = zh.substring(start).trim();
  if (tail.isNotEmpty) segs.add(tail);

  final clauses = <String>[];
  for (final seg in segs) {
    if (seg.contains('（僻') || seg.contains('(僻') || seg.contains('此义非 KBBI')) {
      continue;
    }
    final core = seg.replaceAll(_kParensRe, '').trim();
    if (core.isEmpty) continue;
    for (final part in core.split(_kClauseSplitRe)) {
      final p = part.trim();
      if (p.isNotEmpty) clauses.add(p);
    }
  }
  return clauses;
}

List<String> classifyTopics({required String word, required String zh}) {
  final clauses = _cleanZhClauses(zh);
  final out = <String>[];

  for (final t in _kTopics) {
    final wordScore = _scoreId(word, t.idKw);
    var zhScore = 0;
    if (clauses.isNotEmpty) {
      for (final kw in t.zhKw) {
        if (kw.length == 1) {
          if (_kSafe1.contains(kw) && clauses.contains(kw)) {
            zhScore = 85;
            break;
          }
        } else {
          final negs = _kNeg[kw] ?? const <String>[];
          if (negs.isNotEmpty && negs.any((ng) => zh.contains(ng))) {
            continue;
          }
          if (clauses.any((cl) => cl.contains(kw))) {
            zhScore = 85;
            break;
          }
        }
      }
    }
    if (wordScore + zhScore >= 80) out.add(t.name);
  }
  return out;
}
