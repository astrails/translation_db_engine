desc "synchronise po files with db, creating keys and translations that do not exist"
task :sync_po_to_db => :environment do
  folder = ENV['FOLDER']||'locale'

  gem 'grosser-pomo', '>=0.5.1'
  require 'pomo'
  require 'pathname'

  #find all files we want to read
  po_files = []
  Pathname.new(folder).find do |p|
    next unless p.to_s =~ /\.po$/
    po_files << p
  end

  # In most cases translations can easily fit in memory. we can greatly improve
  # performance of this task by preloading them all at once
  keys = TranslationKey.all(:include => :translations).index_by(&:key)

  #insert all their translation into the db
  po_files.each do |p|
    #read translations from po-files
    locale = p.dirname.basename.to_s
    next unless locale =~ /^[a-z]{2}([-_][a-z]{2})?$/i
    puts "Reading #{p.to_s}"
    translations = Pomo::PoFile.parse(p.read)

    #add all non-fuzzy translations to the database
    translations.reject(&:fuzzy?).each do |t|
      next if t.msgid.blank? #atm do not insert metadata

      msgid = t.msgid.to_json

      key = keys[msgid] ||= TranslationKey.create!(:key_value => t.msgid)

      if translation = key.translations.detect{|text| text.locale == locale}
        # existing translation
        # only by a non-empty .po translation
        next if [*t.msgstr].all?(&:blank?) # po has no translation. leave db alone
        next if t.msgstr == translation.text_value # po and db are the same
        next unless translation.text_value.blank? # don't touch existing db translations

        puts "Updating translation #{locale}:#{msgid} = #{t.msgstr.to_json} [was #{translation.text}]"
        translation.text_value = t.msgstr
        translation.save!
      else
        # new translation
        puts "Creating translation #{locale}:#{msgid} = #{t.msgstr.to_json}"
        key.translations.create!(:locale => locale, :text_value => t.msgstr)
      end

    end
  end
end