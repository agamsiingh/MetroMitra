import 'package:metro_core/src/model/enums.dart';

/// Language data for the offline assistant (docs/ai.md): question words in
/// English, Hinglish (romanised Hindi) and Hindi. **No metro data** lives here
/// (no station, line, place, fare or time); places are always resolved
/// through the dataset's search index.
///
/// Kept as Dart constants instead of YAML assets so metro_core stays free of
/// file IO (ADR-061).
abstract final class AssistantLexicon {
  /// Words (and two-word phrases, joined by a space) that point to an intent,
  /// with a weight. The highest total wins; see [intentPriority] for ties.
  static const intentWords = <AssistantIntentWord, Map<String, int>>{
    AssistantIntentWord.route: {
      'route': 3,
      'reach': 3,
      'directions': 3,
      'way': 2,
      'go': 2,
      'get': 1,
      'travel': 2,
      'how long': 4,
      'kitna time': 4,
      'kitni der': 4,
      'kitna samay': 4,
      'how do': 2,
      'how to': 2,
      'how can': 2,
      'take me': 3,
      'kaise': 2,
      'jaun': 3,
      'jau': 3,
      'jaaun': 3,
      'jaye': 2,
      'jayen': 2,
      'jana': 2,
      'jaana': 2,
      'jaana hai': 3,
      'jana hai': 3,
      'pahunchu': 3,
      'pahuchu': 3,
      'pahunche': 3,
      'rasta': 3,
      'raasta': 3,
      'कैसे': 2,
      'जाऊं': 3,
      'जाऊँ': 3,
      'जाना': 2,
      'पहुंचूं': 3,
      'पहुँचूँ': 3,
      'पहुंचे': 3,
      'रास्ता': 3,
    },
    AssistantIntentWord.nearest: {
      'nearest': 4,
      'nearby': 4,
      'closest': 4,
      'near me': 4,
      'around me': 4,
      'paas': 3,
      'pass': 2,
      'nazdeek': 4,
      'najdik': 4,
      'nazdik': 4,
      'पास': 3,
      'नज़दीक': 4,
      'नजदीक': 4,
      'नज़दीकी': 4,
      'नजदीकी': 4,
    },
    AssistantIntentWord.gate: {
      'gate': 4,
      'gates': 4,
      'exit': 4,
      'exits': 4,
      'entry': 3,
      'entrance': 3,
      'nikas': 4,
      'nikasi': 4,
      'darwaza': 3,
      'गेट': 4,
      'निकास': 4,
      'दरवाज़ा': 3,
      'दरवाजा': 3,
    },
    AssistantIntentWord.platform: {
      'platform': 5,
      'platforms': 5,
      'pf': 4,
      'platfarm': 5,
      'प्लेटफॉर्म': 5,
      'प्लेटफ़ॉर्म': 5,
      'प्लेटफार्म': 5,
    },
    AssistantIntentWord.fare: {
      'fare': 5,
      'fares': 5,
      'ticket': 3,
      'price': 4,
      'cost': 4,
      'how much': 3,
      'kiraya': 5,
      'kiraaya': 5,
      'kitne paise': 5,
      'kitna paisa': 5,
      'kitna': 1,
      'किराया': 5,
      'टिकट': 3,
      'कितने पैसे': 5,
    },
    AssistantIntentWord.firstLast: {
      'first': 4,
      'last': 4,
      'earliest': 4,
      'latest': 3,
      'timing': 3,
      'timings': 3,
      'pehli': 4,
      'pahli': 4,
      'aakhri': 4,
      'akhri': 4,
      'akhiri': 4,
      'antim': 4,
      'पहली': 4,
      'आखिरी': 4,
      'आख़िरी': 4,
      'अंतिम': 4,
      'समय': 2,
    },
    AssistantIntentWord.interchange: {
      'change': 4,
      'interchange': 5,
      'transfer': 4,
      'switch': 3,
      'badalna': 4,
      'badlu': 4,
      'badalni': 4,
      'badalu': 4,
      'बदलनी': 4,
      'बदलूं': 4,
      'बदलूँ': 4,
      'बदलना': 4,
      'इंटरचेंज': 5,
    },
    AssistantIntentWord.facilities: {
      'toilet': 5,
      'toilets': 5,
      'washroom': 5,
      'restroom': 5,
      'bathroom': 5,
      'loo': 4,
      'atm': 5,
      'water': 3,
      'drinking water': 5,
      'help desk': 5,
      'helpdesk': 5,
      'cloakroom': 5,
      'first aid': 5,
      'shop': 3,
      'shops': 3,
      'facility': 4,
      'facilities': 4,
      'suvidha': 4,
      'suvidhaen': 4,
      'shauchalay': 5,
      'paani': 3,
      'pani': 3,
      'शौचालय': 5,
      'टॉयलेट': 5,
      'एटीएम': 5,
      'पानी': 3,
      'सुविधा': 4,
      'सुविधाएं': 4,
      'सुविधाएँ': 4,
    },
    AssistantIntentWord.accessibility: {
      'lift': 5,
      'lifts': 5,
      'elevator': 5,
      'elevators': 5,
      'wheelchair': 5,
      'ramp': 4,
      'escalator': 4,
      'escalators': 4,
      'accessible': 4,
      'accessibility': 5,
      'step free': 5,
      'लिफ्ट': 5,
      'लिफ़्ट': 5,
      'व्हीलचेयर': 5,
      'रैंप': 4,
    },
    AssistantIntentWord.parking: {'parking': 6, 'पार्किंग': 6},
    AssistantIntentWord.lineInfo: {
      'stations': 2,
      'stops': 2,
      'stations on': 3,
      'line stations': 3,
      'kaun se station': 3,
      'स्टेशन कौन': 3,
    },
  };

  /// Ties are broken by this order (more specific first).
  static const intentPriority = <AssistantIntentWord>[
    AssistantIntentWord.platform,
    AssistantIntentWord.gate,
    AssistantIntentWord.firstLast,
    AssistantIntentWord.fare,
    AssistantIntentWord.parking,
    AssistantIntentWord.accessibility,
    AssistantIntentWord.facilities,
    AssistantIntentWord.interchange,
    AssistantIntentWord.nearest,
    AssistantIntentWord.lineInfo,
    AssistantIntentWord.route,
  ];

  /// Words before a place that make it the start of a trip.
  static const fromBefore = {'from', 'via'};

  /// Words after a place that make it the start of a trip (Hindi word order).
  static const fromAfter = {'se', 'say', 'से'};

  /// Words before a place that make it the destination.
  static const toBefore = {'to', 'for', 'till', 'until', 'towards', 'reach'};

  /// Words after a place that make it the destination.
  static const toAfter = {
    'tak',
    'ko',
    'kaise',
    'jana',
    'jaana',
    'ki',
    'ke',
    'की',
    'के',
    'तक',
    'को',
    'कैसे',
    'जाना',
  };

  /// Words around a place that make it "the station asked about".
  static const atBefore = {'at', 'in', 'on', 'of'};
  static const atAfter = {'par', 'pe', 'mein', 'me', 'पर', 'पे', 'में'};

  /// "first" / "last" metro.
  static const firstWords = {
    'first',
    'earliest',
    'pehli',
    'pahli',
    'पहली',
    'subah',
  };
  static const lastWords = {
    'last',
    'latest',
    'aakhri',
    'akhri',
    'akhiri',
    'antim',
    'आखिरी',
    'आख़िरी',
    'अंतिम',
  };

  /// Smart-card fare wanted.
  static const cardWords = {'card', 'smart', 'smartcard', 'कार्ड'};

  /// Facility words -> facility type.
  static const facilityTypes = <String, FacilityType>{
    'toilet': FacilityType.toilet,
    'toilets': FacilityType.toilet,
    'washroom': FacilityType.toilet,
    'restroom': FacilityType.toilet,
    'bathroom': FacilityType.toilet,
    'loo': FacilityType.toilet,
    'shauchalay': FacilityType.toilet,
    'शौचालय': FacilityType.toilet,
    'टॉयलेट': FacilityType.toilet,
    'atm': FacilityType.atm,
    'एटीएम': FacilityType.atm,
    'water': FacilityType.drinkingWater,
    'drinking water': FacilityType.drinkingWater,
    'paani': FacilityType.drinkingWater,
    'pani': FacilityType.drinkingWater,
    'पानी': FacilityType.drinkingWater,
    'help desk': FacilityType.helpDesk,
    'helpdesk': FacilityType.helpDesk,
    'cloakroom': FacilityType.cloakroom,
    'first aid': FacilityType.firstAid,
    'shop': FacilityType.shop,
    'shops': FacilityType.shop,
  };

  /// Words that are never part of a place name in a question: grammar and
  /// question words. Intent words and markers above are excluded too.
  static const filler = {
    // English
    'a', 'an', 'the', 'is', 'are', 'was', 'there', 'any', 'what', 'whats',
    'which', 'where', 'when', 'who', 'how', 'do', 'does', 'did', 'i', 'me',
    'my', 'we', 'you', 'can', 'could', 'should', 'would', 'will', 'please',
    'tell', 'show', 'find', 'need', 'want', 'know', 'give', 'get', 'go',
    'take', 'metro', 'train', 'trains', 'station', 'stn', 'stations', 'line',
    'number', 'no', 'much', 'many', 'it', 'its', 'this', 'that', 'and',
    'or', 'with', 'by', 'about', 'next', 'time', 'today', 'now', 'have',
    'has', 'available', 'open', 'side', 'one', 'some', 'use', 'better',
    'best', 'for', 'to', 'from', 'at', 'in', 'on', 'of', 'via', 'till',
    'until', 'towards', 'near', 'around', 'list', 'all', 'stop',
    // Hinglish
    'kya', 'hai', 'hain', 'he', 'h', 'ho', 'hoga', 'hogi', 'kab', 'kaun',
    'kaunsa', 'konsa', 'kaunse', 'konse', 'sa', 'si', 'se', 'kahan', 'kaha',
    'kidhar', 'mujhe', 'muje', 'mai', 'main', 'mein', 'hum', 'ka',
    'ki', 'ke', 'ko', 'tak', 'par', 'pe', 'wala', 'wali', 'wale', 'batao',
    'bataiye', 'bataye', 'chahiye', 'aur', 'ya', 'bhi', 'koi', 'liye',
    'lene', 'lena', 'jaane', 'jaate', 'milegi', 'milega', 'chalti',
    'chalegi', 'say', 'yahan', 'yaha', 'abhi', 'aaj', 'mere', 'lagenge',
    'lagega', 'lagta', 'lagti', 'lagegi', 'sabse', 'jata', 'jati', 'hota',
    // Hindi
    'क्या', 'है', 'हैं', 'कब', 'कौन', 'कौनसा', 'कौन-सा', 'सा', 'सी', 'से',
    'कहाँ', 'कहां', 'मुझे', 'मैं', 'में', 'का', 'की', 'के', 'को', 'तक', 'पर',
    'पे', 'वाला', 'वाली', 'बताओ', 'बताइए', 'चाहिए', 'और', 'या', 'भी', 'कोई',
    'लिए', 'मेट्रो', 'स्टेशन', 'ट्रेन', 'लाइन', 'नंबर', 'मिलेगी', 'चलती',
    'मेरे', 'अभी', 'आज',
  };

  /// Line words allowed at the end of a line name ("Blue Line").
  static const lineWords = {'line', 'लाइन'};
}

/// Intents as the lexicon knows them (mapped to `AssistantIntent`).
enum AssistantIntentWord {
  route,
  nearest,
  gate,
  platform,
  fare,
  firstLast,
  interchange,
  facilities,
  accessibility,
  parking,
  lineInfo,
}
