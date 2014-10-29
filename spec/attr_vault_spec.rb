require 'spec_helper'
require 'json'

describe AttrVault do
  context "with a single encrypted column" do
    let(:key_id)   { '80a8571b-dc8a-44da-9b89-caee87e41ce2' }
    let(:key_data) {
      [{
        id: key_id,
        value: 'aFJDXs+798G7wgS/nap21LXIpm/Rrr39jIVo2m/cdj8=',
        created_at: Time.now }].to_json
    }
    let(:item)   {
      # the let form can't be evaluated inside the class definition
      # because Ruby scoping rules were written by H.P. Lovecraft, so
      # we create a local here to work around that
      k = key_data
      Class.new(Sequel::Model(:items)) do
        include AttrVault
        vault_keyring k
        vault_attr :secret
      end
    }

    context "with a new object" do
      it "does not affect other attributes" do
        not_secret = 'jimi hendrix was rather talented'
        s = item.create(not_secret: not_secret)
        s.reload
        expect(s.not_secret).to eq(not_secret)
        expect(s.this.where(not_secret: not_secret).count).to eq 1
      end

      it "encrypts non-empty values" do
        secret = 'lady gaga? also rather talented'
        s = item.create(secret: secret)
        s.reload
        expect(s.secret).to eq(secret)
        s.columns.each do |col|
          expect(s.this.where(Sequel.cast(Sequel.cast(col, :text), :bytea) => secret).count).to eq 0
        end
      end

      it "stores empty values as empty" do
        secret = ''
        s = item.create(secret: secret)
        s.reload
        expect(s.secret).to eq('')
        expect(s.secret_encrypted).to eq('')
      end

      it "stores nil values as nil" do
        s = item.create(secret: nil)
        s.reload
        expect(s.secret).to be_nil
        expect(s.secret_encrypted).to be_nil
      end

      it "stores the key id" do
        secret = 'it was professor plum with the wrench in the library'
        s = item.create(secret: secret)
        s.reload
        expect(s.key_id).to eq(key_id)
      end
    end

    context "with an existing object" do
      it "does not affect other attributes" do
        not_secret = 'soylent is not especially tasty'
        s = item.create
        s.update(not_secret: not_secret)
        s.reload
        expect(s.not_secret).to eq(not_secret)
        expect(s.this.where(not_secret: not_secret).count).to eq 1
      end

      it "encrypts non-empty values" do
        secret = 'soylent green is made of people'
        s = item.create
        s.update(secret: secret)
        s.reload
        expect(s.secret).to eq(secret)
        s.columns.each do |col|
          expect(s.this.where(Sequel.cast(Sequel.cast(col, :text), :bytea) => secret).count).to eq 0
        end
      end

      it "stores empty values as empty" do
        s = item.create(secret: "darth vader is luke's father")
        s.update(secret: '')
        s.reload
        expect(s.secret).to eq('')
        expect(s.secret_encrypted).to eq('')
      end

      it "leaves nil values as nil" do
        s = item.create(secret: "dr. crowe was dead all along")
        s.update(secret: nil)
        s.reload
        expect(s.secret).to be_nil
        expect(s.secret_encrypted).to be_nil
      end

      it "stores the key id" do
        secret = 'animal style'
        s = item.create
        s.update(secret: secret)
        s.reload
        expect(s.key_id).to eq(key_id)
      end
    end
  end

  context "with multiple encrypted columns" do
    let(:key_data) {
      [{
        id: '80a8571b-dc8a-44da-9b89-caee87e41ce2',
        value: 'aFJDXs+798G7wgS/nap21LXIpm/Rrr39jIVo2m/cdj8=',
        created_at: Time.now }].to_json
    }
    let(:item)   {
      k = key_data
      Class.new(Sequel::Model(:items)) do
        include AttrVault
        vault_keyring k
        vault_attr :secret
        vault_attr :other
      end
    }

    it "does not clobber other attributes" do
      secret1 = "superman is really mild-mannered reporter clark kent"
      secret2 = "batman is really millionaire playboy bruce wayne"
      s = item.create(secret: secret1)
      s.reload
      expect(s.secret).to eq secret1
      s.update(other: secret2)
      s.reload
      expect(s.secret).to eq secret1
      expect(s.other).to eq secret2
    end
  end

  context "with items encrypted with an older key" do
    let(:key1_id)  { '80a8571b-dc8a-44da-9b89-caee87e41ce2' }
    let(:key1)     {
      {
       id: key1_id,
       value: 'aFJDXs+798G7wgS/nap21LXIpm/Rrr39jIVo2m/cdj8=',
       created_at: Time.new(2014, 1, 1, 0, 0, 0)
      }
    }

    let(:key2_id)  { '0a85781b-d8ac-4a4d-89b9-acee874e1ec2' }
    let(:key2)     {
      {
       id: key2_id,
       value: 'hUL1orBBRckZOuSuptRXYMV9lx5Qp54zwFUVwpwTpdk=',
       created_at: Time.new(2014, 2, 1, 0, 0, 0)
      }
    }
    let(:partial_keyring) {
      [key1].to_json
    }

    let(:full_keyring) {
      [key1, key2].to_json
    }
    let(:item1) {
      k = partial_keyring
      Class.new(Sequel::Model(:items)) do
        include AttrVault
        vault_keyring k
        vault_attr :secret
        vault_attr :other
      end
    }
    let(:item2) {
      k = full_keyring
      Class.new(Sequel::Model(:items)) do
        include AttrVault
        vault_keyring k
        vault_attr :secret
        vault_attr :other
      end
    }

    it "rewrites the items using the current key" do
      secret1 = 'mrs. doubtfire is really a man'
      secret2 = 'tootsie? also a man'
      record = item1.create(secret: secret1)
      expect(record.key_id).to eq key1_id
      expect(record.secret).to eq secret1

      old_secret_encrypted = record.secret_encrypted
      old_secret_hmac = record.secret_hmac

      new_key_record = item2[record.id]
      new_key_record.update(secret: secret2)
      new_key_record.reload

      expect(new_key_record.key_id).to eq key2_id
      expect(new_key_record.secret).to eq secret2
      expect(new_key_record.secret_encrypted).not_to eq old_secret_encrypted
      expect(new_key_record.secret_hmac).not_to eq old_secret_hmac
    end

    it "rewrites the items using the current key even if they are not updated" do
      secret1 = 'the planet of the apes is really earth'
      secret2 = 'the answer is 42'
      record = item1.create(secret: secret1)
      expect(record.key_id).to eq key1_id
      expect(record.secret).to eq secret1

      old_secret_encrypted = record.secret_encrypted
      old_secret_hmac = record.secret_hmac

      new_key_record = item2[record.id]
      new_key_record.update(other: secret2)
      new_key_record.reload

      expect(new_key_record.key_id).to eq key2_id
      expect(new_key_record.secret).to eq secret1
      expect(new_key_record.secret_encrypted).not_to eq old_secret_encrypted
      expect(new_key_record.secret_hmac).not_to eq old_secret_hmac
      expect(new_key_record.other).to eq secret2
    end
  end

  context "with renamed database fields" do
    let(:key_data) {
      [{
        id: '80a8571b-dc8a-44da-9b89-caee87e41ce2',
        value: 'aFJDXs+798G7wgS/nap21LXIpm/Rrr39jIVo2m/cdj8=',
        created_at: Time.now }].to_json
    }

    it "supports renaming the encrypted and hmac fields" do
      k = key_data
      item = Class.new(Sequel::Model(:items)) do
        include AttrVault
        vault_keyring k
        vault_attr :classified_info,
          encrypted_field: :secret_encrypted,
          hmac_field: :secret_hmac
      end

      secret = "we've secretly replaced the fine coffee they usually serve with Folgers Crystals"
      s = item.create(classified_info: secret)
      s.reload
      expect(s.classified_info).to eq secret
      expect(s.secret_encrypted).not_to eq secret
      expect(s.secret_hmac).not_to be_nil
    end

    it "supports renaming the key id field" do
      k = key_data
      item = Class.new(Sequel::Model(:items)) do
        include AttrVault
        vault_keyring k, key_field: :alt_key_id
        vault_attr :secret
      end

      secret = "up up down down left right left right b a"
      s = item.create(secret: secret)
      s.reload
      expect(s.secret).to eq secret
      expect(s.secret_encrypted).not_to eq secret
      expect(s.secret_hmac).not_to be_nil
      expect(s.alt_key_id).not_to be_nil
      expect(s.key_id).to be_nil
    end
  end
end