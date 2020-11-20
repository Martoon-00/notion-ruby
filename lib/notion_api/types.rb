require_relative "utils"
require_relative "block"
require "httparty"
require "date"
require "logger"

$LOGGER = Logger.new(STDOUT)
$LOGGER.level = Logger::INFO

module Notion
  class BlockTemplate < Block
    #! Base Template for all blocks. Inherits core methods from the Block class defined in block.rb
    include Utils

    attr_reader :type, :id, :title, :parent_id
    $Components = Utils::Components.new

    def initialize(id, title, parent_id)
      @id = id
      @title = title
      @parent_id = parent_id
    end # initialize

    def title=(new_title)
      #! Change the title of a block.
      #! new_title -> new title for the block : ``str``
      request_id = extract_id(SecureRandom.hex(n = 16))
      transaction_id = extract_id(SecureRandom.hex(n = 16))
      space_id = extract_id(SecureRandom.hex(n = 16))
      update_title(new_title.to_s, request_id, transaction_id, space_id)
      $LOGGER.info("Title changed from '#{self.title}' to '#{new_title}'")
      @title = new_title
      return true
    end # title=

    def update_title(new_title, request_id, transaction_id, space_id)
      #! Helper method for sending POST request to change title of block.
      #! new_title -> new title for the block : ``str``
      #! request_id -> the unique ID for the request. Generated using SecureRandom : ``str``
      #! transaction_id -> the unique ID for the transactions. Generated using SecureRandom: ``str``
      # setup cookies, headers, and grab/create static vars for request
      cookies = @@options["cookies"]
      headers = @@options["headers"]
      request_url = @@method_urls[:UPDATE_BLOCK]
      timestamp = DateTime.now.strftime("%Q") # 13-second timestamp (unix timestamp in MS), to get it in seconds we can use Time.now.to_i

      # set unique IDs for request
      request_ids = {
        :request_id => request_id,
        :transaction_id => transaction_id,
        :space_id => space_id,
      }

      # build and set operations to send to Notion
      title_hash = $Components.title(@id, new_title)
      last_edited_time_parent_hash = $Components.last_edited_time(@parent_id)
      last_edited_time_child_hash = $Components.last_edited_time(@id)
      operations = [
        title_hash,
        last_edited_time_parent_hash,
        last_edited_time_child_hash,
      ]

      request_body = build_payload(operations, request_ids) # defined in utils.rb

      response = HTTParty.post(
        request_url,
        :body => request_body.to_json,
        :cookies => cookies,
        :headers => headers,
      )
      return response.body
    end # update_title

    def convert(block_class_to_convert_to)
      #! convert a block from its current type to another.
      #! block_class_to_convert_to -> the type of block to convert to : ``cls``
      if self.type == block_class_to_convert_to.notion_type
        # if converting to same type, skip and return self
        return self
      else
        # setup cookies, headers, and grab/create static vars for request
        cookies = @@options["cookies"]
        headers = @@options["headers"]
        request_url = @@method_urls[:UPDATE_BLOCK]
        timestamp = DateTime.now.strftime("%Q") # 13-second timestamp (unix timestamp in MS), to get it in seconds we can use Time.not.to_i

        # set random IDs for request
        request_id = extract_id(SecureRandom.hex(n = 16))
        transaction_id = extract_id(SecureRandom.hex(n = 16))
        space_id = extract_id(SecureRandom.hex(n = 16))
        request_ids = {
          :request_id => request_id,
          :transaction_id => transaction_id,
          :space_id => space_id,
        }

        # build hash's that contain the operations to send to Notions backend
        convert_type_hash = $Components.convert_type(@id, block_class_to_convert_to)
        last_edited_time_parent_hash = $Components.last_edited_time(@parent_id)
        last_edited_time_child_hash = $Components.last_edited_time(@id)

        operations = [
          convert_type_hash,
          last_edited_time_parent_hash,
          last_edited_time_child_hash,
        ]

        request_body = build_payload(operations, request_ids)
        response = HTTParty.post(
          request_url,
          :body => request_body.to_json,
          :cookies => cookies,
          :headers => headers,
        )

        return block_class_to_convert_to.new(@id, @title, @parent_id)
      end
    end

    def duplicate(after = nil)
      #! duplicate the block that this method is invoked upon.
      #! after -> the block to place the duplicated block after. Can be any valid Block ID! : ``str``
      cookies = @@options["cookies"]
      headers = @@options["headers"]
      request_url = @@method_urls[:UPDATE_BLOCK]
      timestamp = DateTime.now.strftime("%Q") # 13-second timestamp (unix timestamp in MS), to get it in seconds we can use Time.not.to_i

      new_block_id = extract_id(SecureRandom.hex(n = 16))
      request_id = extract_id(SecureRandom.hex(n = 16))
      transaction_id = extract_id(SecureRandom.hex(n = 16))
      space_id = extract_id(SecureRandom.hex(n = 16))

      root_children = children_ids(@id)
      sub_children = []
      root_children.each { |root_id| sub_children.push(children_ids(root_id)) }

      request_ids = {
        :request_id => request_id,
        :transaction_id => transaction_id,
        :space_id => space_id,
      }
      body = {
        :pageId => @id,
        :chunkNumber => 0,
        :limit => 100,
        :verticalColumns => false,
      }

      user_notion_id = get_notion_id(body)

      block = after ? get_block(after) : self # allows dev to place block anywhere!

      duplicate_hash = $Components.duplicate(title, block.id, new_block_id, user_notion_id, root_children)
      set_parent_alive_hash = $Components.set_parent_to_alive(block.parent_id, new_block_id)
      block_location_hash = $Components.block_location(block.parent_id, block.id, new_block_id, after)
      last_edited_time_parent_hash = $Components.last_edited_time(block.parent_id)
      last_edited_time_child_hash = $Components.last_edited_time(block.id)

      operations = [
        duplicate_hash,
        set_parent_alive_hash,
        block_location_hash,
        last_edited_time_parent_hash,
        last_edited_time_child_hash,
      ]

      request_body = build_payload(operations, request_ids)
      response = HTTParty.post(
        request_url,
        :body => request_body.to_json,
        :cookies => cookies,
        :headers => headers,
      )
      return {}
    end

    def create(block_type, block_title, after = nil)
      #! create a new block
      #! block_type -> the type of block to create : ``cls``
      #! block_title -> the title of the new block : ``str``
      #! loc -> the block_id that the new block should be placed after. ``str``
      cookies = @@options["cookies"]
      headers = @@options["headers"]
      timestamp = DateTime.now.strftime("%Q")

      new_block_id = extract_id(SecureRandom.hex(n = 16))
      request_id = extract_id(SecureRandom.hex(n = 16))
      transaction_id = extract_id(SecureRandom.hex(n = 16))
      space_id = extract_id(SecureRandom.hex(n = 16))

      request_ids = {
        :request_id => request_id,
        :transaction_id => transaction_id,
        :space_id => space_id,
      }

      body = {
        :pageId => @id,
        :chunkNumber => 0,
        :limit => 100,
        :verticalColumns => false,
      }

      user_notion_id = get_notion_id(body)

      create_hash = $Components.create(new_block_id, block_type.notion_type)
      set_parent_alive_hash = $Components.set_parent_to_alive(@id, new_block_id)
<<<<<<< Updated upstream
      block_location_hash = $Components.block_location(@id, @id, new_block_id, after)
      last_edited_time_parent_hash = $Components.last_edited_time(@parent_id)
=======
      block_location_hash = $Components.block_location_add(@id, @id, new_block_id, command="listAfter")
      last_edited_time_parent_hash = $Components.last_edited_time(self.type == "page" ? @id : @parent_id) # if PageBlock, the parent IS the the page the method is invoked on.
>>>>>>> Stashed changes
      last_edited_time_child_hash = $Components.last_edited_time(@id)
      title_hash = $Components.title(new_block_id, block_title)

      operations = [
        create_hash,
        set_parent_alive_hash,
        block_location_hash,
        last_edited_time_parent_hash,
        last_edited_time_child_hash,
        title_hash,
      ]

      request_url = @@method_urls[:UPDATE_BLOCK]
      request_body = build_payload(operations, request_ids)
      response = HTTParty.post(
        request_url,
        :body => request_body.to_json,
        :cookies => cookies,
        :headers => headers,
      )
      new_block = block_type.new(new_block_id, block_title, @id)
      # new_block = Notion.const_get(BLOCK_TYPES[block_type]).new(block_type, new_block_id, block_title, @parent_id, @token_v2)
      # styles.empty? ? nil : new_block.update(styles)
      return new_block
    end # create
  end # BlockTemplate

  class DividerBlock < BlockTemplate
    # divider block: ---------
    @@notion_type = "divider"
    def self.notion_type
      @@notion_type
    end
  end

  class TodoBlock < BlockTemplate
    # To-Do block: best for checklists and tracking to-dos.
    @@notion_type = "to_do"

    def self.notion_type
      @@notion_type
    end

    def self.name
      #! change the class.name attribute
      @@notion_type
    end

    def checked=(checked_value)
      #! change the checked property of the Todo Block.
      #! checked_value -> boolean value used to determine whether the block should be checked [yes, 1, true] or not [no, 0, false] : ``bool | str``
      # set static variables for request
      cookies = @@options["cookies"]
      headers = @@options["headers"]
      timestamp = DateTime.now.strftime("%Q")
      request_url = @@method_urls[:UPDATE_BLOCK]

      # set unique values for request
      request_id = extract_id(SecureRandom.hex(n = 16))
      transaction_id = extract_id(SecureRandom.hex(n = 16))
      space_id = extract_id(SecureRandom.hex(n = 16))
      request_ids = {
        :request_id => request_id,
        :transaction_id => transaction_id,
        :space_id => space_id,
      }

      if ["yes", "no"].include?(checked_value.downcase)
        checked_hash = $Components.checked_todo(@id, checked_value.downcase)
        last_edited_time_parent_hash = $Components.last_edited_time(@parent_id)
        last_edited_time_child_hash = $Components.last_edited_time(@id)
        p self.notion_type, @@notion_type

        operations = [
          checked_hash,
          last_edited_time_parent_hash,
          last_edited_time_child_hash,
        ]
        request_body = build_payload(operations, request_ids)
        response = HTTParty.post(
          request_url,
          :body => request_body.to_json,
          :cookies => cookies,
          :headers => headers,
        )
        return true
      else
        return false
        $LOGGER.error("#{checked_value} is not an accepted input value. If you want to check a To-Do block, use one of the following: 1, 'yes', of true. If you want to un-check a To-Do block, use one of the following: 0, 'no', false.")
      end
    end
  end

  class CodeBlock < BlockTemplate
    # Code block: used to store code, should be assigned a coding language.
    @@notion_type = "code"

    def self.notion_type
      @@notion_type
    end
  end

  class HeaderBlock < BlockTemplate
    # Header block: H1
    @@notion_type = "header"
    def self.notion_type
      @@notion_type
    end
  end

  class SubHeaderBlock < BlockTemplate
    # SubHeader Block: H2
    @@notion_type = "sub_header"
    def self.notion_type
      @@notion_type
    end
  end

  class SubSubHeaderBlock < BlockTemplate
    # Sub-Sub Header Block: H3
    @@notion_type = "sub_sub_header"
    def self.notion_type
      @@notion_type
    end
  end

  class PageBlock < BlockTemplate
    @@notion_type = "page"

    def self.notion_type
      @@notion_type
    end

    def type
      @@notion_type
    end
  end

  class ToggleBlock < BlockTemplate
    # Toggle block: best for storing children blocks
    @@notion_type = "toggle"
    def self.notion_type
      @@notion_type
    end
  end

  class BulletedBlock < BlockTemplate
    # Bullet list block: best for an unordered list
    @@notion_type = "bulleted_list"
    def self.notion_type
      @@notion_type
    end
  end

  class NumberedBlock < BlockTemplate
    # Numbered list Block: best for an ordered list
    @@notion_type = "numbered_list"
    def self.notion_type
      @@notion_type
    end
  end

  class QuoteBlock < BlockTemplate
    # best for memorable information
    @@notion_type = "quote"
    def self.notion_type
      @@notion_type
    end
  end

  class CalloutBlock < BlockTemplate
    # same as quote... works similarly to page block
    @@notion_type = "callout"
    def self.notion_type
      @@notion_type
    end
  end

  class LatexBlock < BlockTemplate
    # simiilar to code block but for mathematical functions.
    @@notion_type = "equation"
    def self.notion_type
      @@notion_type
    end
  end

  class TextBlock < BlockTemplate
    # good for just about anything (-:
    @@notion_type = "text"
    def self.notion_type
      @@notion_type
    end
  end

  class ImageBlock < BlockTemplate
    # good for visual information
    @@notion_type = "image"
    def self.notion_type
      @@notion_type
    end
  end

  class TableOfContentsBlock < BlockTemplate
    # maps out the headers - sub-headers - sub-sub-headers on the page
    @@notion_type = "table_of_contents"
    def self.notion_type
      @@notion_type
    end
  end

  class ColumnListBlock < BlockTemplate
    #TODO: no use case for this yet.
    @@notion_type = "column_list"
    def self.notion_type
      @@notion_type
    end
  end

  class ColumnBlock < BlockTemplate
    #TODO: no use case for this yet.
    @@notion_type = "column"
    def self.notion_type
      @@notion_type
    end
  end
end # Notion

# gather a list of all the classes defined here...
Classes = Notion.constants.select { |c| Notion.const_get(c).is_a? Class and c.to_s != "BlockTemplate" and c.to_s != "Block" }
notion_types = []
Classes.each { |cls| notion_types.push(Notion.const_get(cls).notion_type) }
BLOCK_TYPES = notion_types.zip(Classes).to_h
